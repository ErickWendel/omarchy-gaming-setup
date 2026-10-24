#!/usr/bin/env python3
"""Reconcile the emulators' non-Steam shortcuts from manifest.json.

Every manifest record with "steam": true gets exactly one shortcut in the
Steam user's shortcuts.vdf, launching the same target as its menu entry.
Shortcuts this module created are tracked by appid in a state file, so a
changed launcher path updates the existing shortcut (keeping its artwork and
play time) instead of adding a second one. Unrelated shortcuts are left as
they are. Steam rewrites shortcuts.vdf when it exits, so install refuses to
run while Steam is running.
"""

import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import zlib

import vdf

COLLECTION_TAG = "Emulators"
# An absolute path up to an Emulation folder, inside or outside quotes.
EMULATION_PATH = re.compile(r'(/[^"\s]*/Emulation)/')

_spec = importlib.util.spec_from_file_location(
    "omarchy_emulators", Path(__file__).resolve().with_name("emulators.py"))
emulators = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(emulators)


def shortcut_appid(exe, name):
    """The unsigned appid Steam gives a shortcut it creates itself."""
    return (zlib.crc32((exe + name).encode()) & 0xFFFFFFFF) | 0x80000000


def signed(appid):
    return appid - (1 << 32) if appid >= 1 << 31 else appid


def unsigned(appid):
    return int(appid) & 0xFFFFFFFF


def steam_is_running():
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text(encoding="utf-8").strip() == "steam":
                return True
        except OSError:
            continue
    return False


def find_config_dir(steam_root, user_id=None):
    """Return the Steam user's config directory, or raise with the reason."""
    pattern = f"{user_id or '*'}/config"
    candidates = sorted(path for path in (steam_root / "userdata").glob(pattern) if path.is_dir())
    # Account 0 is Steam's anonymous placeholder.
    candidates = [path for path in candidates if path.parent.name != "0"]
    if not candidates:
        raise LookupError(f"no Steam user under {steam_root / 'userdata'}; sign in to Steam once")
    if len(candidates) > 1:
        raise LookupError("several Steam users have signed in; set STEAM_USER_ID in config/machine.env")
    return candidates[0]


def load_shortcuts(path):
    if not path.exists():
        return {"shortcuts": {}}
    with path.open("rb") as stream:
        return vdf.binary_load(stream)


def load_state(path):
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return {}
    except ValueError:
        print(f"WARN emulators: ignoring unreadable state file {path}", file=sys.stderr)
        return {}
    return {key: unsigned(value) for key, value in data.get("shortcuts", {}).items()}


def desired_entries(records, places):
    """Return (wanted, blocked): wanted maps manifest id to shortcut fields."""
    wanted, blocked = {}, []
    for record in records:
        if not record.get("steam"):
            continue
        resolved = emulators.resolve_record(record, places)
        if resolved["problems"]:
            blocked.append((record, resolved["problems"]))
            continue
        target = resolved["target"]
        icon = resolved["icon"] if os.path.isabs(resolved["icon"]) else ""
        wanted[record["id"]] = {
            "appname": record["name"],
            "exe": f'"{target}"',
            # Unquoted, as components/pcsx2 writes it for PCSX2 shortcuts.
            "StartDir": os.path.dirname(target),
            "icon": icon,
        }
    return wanted, blocked


def launches_bare(entry, exe):
    """True for a shortcut that starts the emulator itself, not a game in it."""
    return entry.get("exe") == exe and not str(entry.get("LaunchOptions", "")).strip()


def new_entry(fields, appid):
    return {
        "appid": signed(appid),
        "appname": fields["appname"],
        "exe": fields["exe"],
        "StartDir": fields["StartDir"],
        "icon": fields["icon"],
        "ShortcutPath": "",
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "sortas": "",
        "tags": {"0": COLLECTION_TAG},
    }


def reconcile(shortcuts, state, wanted, manifest_ids):
    """Upsert wanted shortcuts in place.

    Returns (changes, new_state). A shortcut is matched first by the appid
    recorded in state, then by an exe without launch options, so a shortcut
    someone added by hand for the same launcher is adopted rather than
    duplicated, while game shortcuts sharing the launcher are left alone. Owned shortcuts
    whose manifest record is gone are removed; owned shortcuts that are only
    blocked (drive not mounted) are kept.
    """
    entries = list(shortcuts.get("shortcuts", {}).values())
    by_appid = {unsigned(entry.get("appid", 0)): entry for entry in entries}
    changes, new_state = [], {}

    for record_id, fields in wanted.items():
        entry = by_appid.get(state.get(record_id))
        if entry is None:
            entry = next((item for item in entries if launches_bare(item, fields["exe"])), None)
        if entry is None:
            appid = shortcut_appid(fields["exe"], fields["appname"])
            entry = new_entry(fields, appid)
            entries.append(entry)
            by_appid[appid] = entry
            changes.append(f"Add Steam shortcut {fields['appname']} ({appid}) -> {fields['exe']}")
        else:
            updated = [key for key, value in fields.items() if entry.get(key) != value]
            # Keep the user's own icon choice once the shortcut exists.
            if "icon" in updated and entry.get("icon"):
                updated.remove("icon")
            for key in updated:
                entry[key] = fields[key]
            tags = entry.setdefault("tags", {})
            if COLLECTION_TAG not in tags.values():
                tags[str(len(tags))] = COLLECTION_TAG
                updated.append("tags")
            if updated:
                changes.append(f"Update Steam shortcut {fields['appname']}: {', '.join(updated)}")
        new_state[record_id] = unsigned(entry["appid"])

    for record_id, appid in state.items():
        if record_id in new_state:
            continue
        if record_id in manifest_ids:
            new_state[record_id] = appid
            continue
        entry = by_appid.get(appid)
        if entry is not None:
            entries.remove(entry)
            changes.append(f"Remove Steam shortcut {entry.get('appname', appid)} (no longer in the manifest)")

    # Steam expects consecutive string keys.
    shortcuts["shortcuts"] = {str(index): entry for index, entry in enumerate(entries)}
    return changes, new_state


def stale_emulation_paths(shortcuts, emulation_root):
    """Shortcuts that point into an Emulation folder outside the live mount."""
    stale = []
    for entry in shortcuts.get("shortcuts", {}).values():
        for key in ("exe", "StartDir", "LaunchOptions"):
            roots = set(EMULATION_PATH.findall(str(entry.get(key, ""))))
            wrong = sorted(root for root in roots if root != emulation_root)
            if wrong:
                stale.append((entry.get("appname", "?"), key, wrong[0]))
                break
    return stale


def atomic_write_binary(path, data):
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            vdf.binary_dump(data, stream)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def write_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump({"version": 1, "shortcuts": state}, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, path)


def report_blocked(blocked, prefix):
    for record, problems in blocked:
        print(f"{prefix} emulators: Steam shortcut for {record['name']} skipped: {'; '.join(problems)}",
              file=sys.stderr if prefix == "ERROR" else sys.stdout)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "check", "dry-run"))
    parser.add_argument("--uuid", required=True, help="GExtended filesystem UUID")
    parser.add_argument("--manifest", default=str(Path(__file__).with_name("manifest.json")))
    parser.add_argument("--steam-root", type=Path, default=Path(os.environ.get(
        "STEAM_ROOT", os.path.expanduser("~/.local/share/Steam"))))
    parser.add_argument("--steam-user", default=os.environ.get("STEAM_USER_ID") or None)
    parser.add_argument("--icons-dir", default=os.path.expanduser("~/.config/EmuDeck/backend/icons"))
    state_home = os.path.expanduser("~/.local/state/omarchy-gaming-setup")
    parser.add_argument("--state-file", type=Path,
                        default=Path(state_home, "emulator-steam-shortcuts.json"))
    parser.add_argument("--backup-root", type=Path, default=Path(os.environ.get(
        "OMARCHY_BACKUP_ROOT", os.path.join(state_home, "backups"))))
    parser.add_argument("--findmnt", default="findmnt")
    parser.add_argument("--ignore-running-steam", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    try:
        records = emulators.load_manifest(args.manifest)
    except (OSError, ValueError, emulators.ManifestError) as error:
        print(f"ERROR emulators: invalid manifest {args.manifest}: {error}", file=sys.stderr)
        return 2
    try:
        config_dir = find_config_dir(args.steam_root, args.steam_user)
    except LookupError as error:
        if args.action == "dry-run":
            print(f"Skip emulator Steam shortcuts: {error}")
            return 0
        level = "FAIL" if args.action == "check" else "ERROR"
        print(f"{level} emulators: {error}", file=sys.stderr if level == "ERROR" else sys.stdout)
        return 1

    mount, read_only = emulators.resolve_mount(args.uuid, args.findmnt)
    places = {"home": str(Path.home()), "icons": args.icons_dir}
    emulation_root = None
    if mount is not None:
        emulation_root = places["emulation"] = os.path.join(mount, "Emulation")
    wanted, blocked = desired_entries(records, places)
    manifest_ids = {record["id"] for record in records if record.get("steam")}

    shortcuts_path = config_dir / "shortcuts.vdf"
    try:
        shortcuts = load_shortcuts(shortcuts_path)
    except (OSError, SyntaxError, ValueError) as error:
        print(f"ERROR emulators: cannot parse {shortcuts_path}: {error}", file=sys.stderr)
        return 1
    state = load_state(args.state_file)
    changes, new_state = reconcile(shortcuts, state, wanted, manifest_ids)

    if args.action == "check":
        failures = 0
        for change in changes:
            failures += 1
            print(f"FAIL emulators: pending: {change}")
        for record, problems in blocked:
            failures += 1
            print(f"FAIL emulators: Steam shortcut for {record['name']}: {'; '.join(problems)}")
        for record_id, fields in wanted.items():
            matches = [entry for entry in shortcuts["shortcuts"].values()
                       if launches_bare(entry, fields["exe"])]
            if len(matches) > 1:
                failures += 1
                print(f"FAIL emulators: {fields['appname']} has {len(matches)} Steam shortcuts")
            elif not changes:
                print(f"OK   emulators: Steam shortcut {fields['appname']} ({new_state[record_id]})")
        for name, key, root in stale_emulation_paths(shortcuts, emulation_root):
            failures += 1
            print(f"FAIL emulators: Steam shortcut {name} uses {root} in {key}, "
                  f"not the live GExtended mount {emulation_root or '(not mounted)'}")
        return 1 if failures else 0

    if args.action == "dry-run":
        for change in changes or ["Emulator Steam shortcuts are up to date"]:
            print(change)
        report_blocked(blocked, "Skip")
        if changes and steam_is_running():
            print("Steam is running; install exits it first (./setup.sh) or must be run with Steam closed")
        return 0

    if not changes:
        print("Emulator Steam shortcuts are up to date")
        if new_state != state:
            write_state(args.state_file, new_state)
        report_blocked(blocked, "ERROR")
        return 1 if blocked else 0
    if steam_is_running() and not args.ignore_running_steam:
        print("ERROR emulators: Steam is running; exit Steam before changing its shortcuts",
              file=sys.stderr)
        return 2
    if shortcuts_path.exists():
        backup_dir = args.backup_root / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-emulator-shortcuts")
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(shortcuts_path, backup_dir / shortcuts_path.name)
        print(f"Backed up {shortcuts_path} to {backup_dir}")
    atomic_write_binary(shortcuts_path, shortcuts)
    write_state(args.state_file, new_state)
    for change in changes:
        print(change)
    report_blocked(blocked, "ERROR")
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main())
