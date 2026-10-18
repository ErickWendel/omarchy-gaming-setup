#!/usr/bin/env python3
"""Generate the emulators' application-menu entries from manifest.json.

EmuDeck writes its .desktop files with every line indented by a tab, which
desktop-file-validate rejects and Omarchy's app launcher does not list. This
module replaces them with project-owned, validated entries whose launchers are
resolved under the GExtended mount found by filesystem UUID.
"""

import argparse
import datetime
import filecmp
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

FILE_PREFIX = "omarchy-gaming-"
OWNER_KEY = "X-Omarchy-Gaming-Setup-Id"
FALLBACK_ICON = "applications-games"
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REQUIRED_FIELDS = ("id", "name", "exec", "icon", "categories")
# Characters that force an Exec argument into double quotes (Desktop Entry
# specification, "The Exec key").
EXEC_RESERVED = set(" \t\n\"'\\><~|&;$*?#()`")


class ManifestError(Exception):
    pass


def load_manifest(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("version") != 1:
        raise ManifestError(f"unsupported manifest version: {data.get('version')!r}")
    seen = set()
    for record in data.get("emulators", []):
        for field in REQUIRED_FIELDS:
            if not isinstance(record.get(field), str) or not record[field]:
                raise ManifestError(f"{record.get('id', '?')}: missing field {field!r}")
        if not ID_PATTERN.match(record["id"]):
            raise ManifestError(f"invalid id: {record['id']!r}")
        if record["id"] in seen:
            raise ManifestError(f"duplicate id: {record['id']!r}")
        seen.add(record["id"])
    return data["emulators"]


def escape_string(value):
    """Escape a value of the specification's string/localestring type."""
    return (value.replace("\\", "\\\\").replace("\n", "\\n")
            .replace("\t", "\\t").replace("\r", "\\r"))


def quote_exec_arg(arg):
    if arg and not EXEC_RESERVED.intersection(arg):
        quoted = arg
    else:
        quoted = '"' + re.sub(r'(["`$\\])', r"\\\1", arg) + '"'
    return quoted.replace("%", "%%")


def exec_value(argv):
    # Exec is a string: argument quoting first, then string escaping.
    return escape_string(" ".join(quote_exec_arg(arg) for arg in argv))


def expand(template, places):
    """Return the template with placeholders filled, or None if one is unknown."""
    try:
        return template.format(**places)
    except KeyError:
        return None


def resolve_record(record, places):
    """Resolve a manifest record into concrete paths and problems."""
    target = expand(record["exec"], places)
    icon = expand(record["icon"], places)
    problems = []
    if target is None:
        problems.append("emulation root is unavailable (GExtended not mounted)")
    elif not (os.path.isfile(target) and os.access(target, os.X_OK)):
        problems.append(f"launcher is missing or not executable: {target}")
    icon_note = None
    if icon is None or (os.path.isabs(icon) and not os.path.isfile(icon)):
        icon_note = f"icon not found ({icon or record['icon']}); using {FALLBACK_ICON}"
        icon = FALLBACK_ICON
    return {"record": record, "target": target, "icon": icon,
            "problems": problems, "icon_note": icon_note}


def render(resolved):
    record = resolved["record"]
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        f"Name={escape_string(record['name'])}",
    ]
    if record.get("generic_name"):
        lines.append(f"GenericName={escape_string(record['generic_name'])}")
    # TryExec hides the entry if the drive holding the launcher goes away.
    lines += [
        f"TryExec={escape_string(resolved['target'])}",
        f"Exec={exec_value([resolved['target']])}",
        f"Icon={escape_string(resolved['icon'])}",
        "Terminal=false",
        f"Categories={record['categories']}",
    ]
    if record.get("keywords"):
        lines.append(f"Keywords={escape_string(record['keywords'])}")
    lines += ["StartupNotify=false", f"{OWNER_KEY}={record['id']}"]
    return "\n".join(lines) + "\n"


def file_name(record_id):
    return f"{FILE_PREFIX}{record_id}.desktop"


def is_malformed_legacy(path):
    """True for an EmuDeck entry whose group header is indented."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return re.search(r"^[ \t]+\[Desktop Entry\]", text, re.MULTILINE) is not None


def owner_id(path):
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    match = re.search(rf"^{re.escape(OWNER_KEY)}=(.*)$", text, re.MULTILINE)
    return match.group(1).strip() if match else None


def has_leading_indent(text):
    return any(line[:1] in (" ", "\t") for line in text.splitlines())


def validate(path, validator):
    result = subprocess.run([validator, str(path)], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    return result.returncode == 0 and "error:" not in output, output


def resolve_mount(uuid, findmnt="findmnt"):
    """Return (target, read_only) for the filesystem UUID, or (None, None)."""
    try:
        result = subprocess.run([findmnt, "-rn", "-S", f"UUID={uuid}", "-o", "TARGET,OPTIONS"],
                                capture_output=True, text=True)
    except OSError:
        return None, None
    line = result.stdout.splitlines()[0] if result.returncode == 0 and result.stdout else ""
    if not line:
        return None, None
    target, _, options = line.partition(" ")
    # findmnt -r escapes spaces in paths as \x20.
    target = re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), target)
    return target, "ro" in options.split(",")


class Plan:
    def __init__(self, records, apps_dir, places):
        self.apps_dir = apps_dir
        self.resolved = [resolve_record(record, places) for record in records]
        manifest_ids = {record["id"] for record in records}
        self.legacy = []
        for item in self.resolved:
            for name in item["record"].get("legacy_files", []):
                path = apps_dir / name
                if path.is_file() and is_malformed_legacy(path):
                    self.legacy.append(path)
            # Valid entries for the same emulator, e.g. an older AppImage
            # integration, would list it twice in the launcher.
            for name in item["record"].get("duplicate_files", []):
                path = apps_dir / name
                if path.is_file() and owner_id(path) is None and path not in self.legacy:
                    self.legacy.append(path)
        self.stale = sorted(
            path for path in apps_dir.glob(f"{FILE_PREFIX}*.desktop")
            if owner_id(path) is not None and owner_id(path) not in manifest_ids)

    def installable(self):
        return [item for item in self.resolved if not item["problems"]]

    def blocked(self):
        return [item for item in self.resolved if item["problems"]]


def backup(path, home, backup_root):
    """Mirror path below backup_root; keep the first copy, timestamp later ones."""
    try:
        relative = path.relative_to(home)
    except ValueError:
        relative = Path(*path.parts[1:])
    destination = backup_root / relative
    if destination.exists() and not filecmp.cmp(path, destination, shallow=False):
        destination = destination.with_name(
            destination.name + "." + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        print(f"Backed up {path} to {destination}")


def dry_run(plan):
    for item in plan.resolved:
        record = item["record"]
        destination = plan.apps_dir / file_name(record["id"])
        if item["problems"]:
            for problem in item["problems"]:
                print(f"Skip {record['name']}: {problem}")
            continue
        content = render(item)
        if not destination.exists():
            action = "Add"
        elif destination.read_text(encoding="utf-8") != content:
            action = "Update"
        else:
            action = "Keep"
        print(f"{action} {destination} -> {item['target']}")
        if item["icon_note"]:
            print(f"  {item['icon_note']}")
    for path in plan.legacy:
        print(f"Retire malformed or duplicate entry {path} (backed up first)")
    for path in plan.stale:
        print(f"Remove stale managed entry {path}")
    return 0


def install(plan, validator, home, backup_root, update_db):
    if shutil.which(validator) is None:
        print(f"ERROR emulators: {validator} is required (pacman -S desktop-file-utils)",
              file=sys.stderr)
        return 1
    failures = 0
    plan.apps_dir.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".omarchy-gaming-", dir=plan.apps_dir.parent))
    try:
        staged = []
        for item in plan.installable():
            name = file_name(item["record"]["id"])
            path = staging / name
            path.write_text(render(item), encoding="utf-8")
            valid, output = validate(path, validator)
            if not valid:
                print(f"ERROR emulators: generated {name} is invalid:\n{output}", file=sys.stderr)
                return 1
            staged.append((path, plan.apps_dir / name, item))
        changed = False
        for source, destination, item in staged:
            if destination.exists() and filecmp.cmp(source, destination, shallow=False):
                continue
            os.chmod(source, 0o644)
            os.replace(source, destination)
            changed = True
            print(f"Installed {destination}")
            if item["icon_note"]:
                print(f"  {item['icon_note']}")
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    for path in plan.legacy + plan.stale:
        backup(path, home, backup_root)
        path.unlink()
        changed = True
        print(f"Removed {path}")
    for item in plan.blocked():
        failures += 1
        for problem in item["problems"]:
            print(f"ERROR emulators: {item['record']['name']} not installed: {problem}",
                  file=sys.stderr)

    if changed and shutil.which(update_db):
        # Its stderr only lists unrelated broken entries.
        subprocess.run([update_db, str(plan.apps_dir)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not changed:
        print("Emulator application entries are up to date")
    return 1 if failures else 0


def check(plan, validator, mount, read_only):
    failures = 0

    def ok(message):
        print(f"OK   emulators: {message}")

    def fail(message):
        nonlocal failures
        failures += 1
        print(f"FAIL emulators: {message}")

    if mount is None:
        fail("GExtended is not mounted; drive launchers cannot start")
    elif read_only:
        fail(f"GExtended at {mount} is read-only; emulators cannot save to it")
    else:
        ok(f"GExtended is mounted read-write at {mount}")
    have_validator = shutil.which(validator) is not None
    if not have_validator:
        fail(f"{validator} is missing (pacman -S desktop-file-utils)")
    for item in plan.resolved:
        record = item["record"]
        path = plan.apps_dir / file_name(record["id"])
        if item["problems"]:
            fail(f"{record['name']}: " + "; ".join(item["problems"]))
            continue
        if not path.is_file():
            fail(f"{record['name']}: {path} is not installed")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if has_leading_indent(text):
            fail(f"{record['name']}: {path} has indented lines")
        elif text != render(item):
            fail(f"{record['name']}: {path} is outdated (rerun install)")
        elif have_validator and not validate(path, validator)[0]:
            fail(f"{record['name']}: {path} fails desktop-file-validate")
        else:
            ok(f"{record['name']} is listed and launches {item['target']}")
    for path in plan.legacy:
        fail(f"malformed or duplicate entry still present: {path}")
    for path in plan.stale:
        fail(f"stale managed entry: {path}")
    return 1 if failures else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "check", "dry-run"))
    parser.add_argument("--uuid", required=True, help="GExtended filesystem UUID")
    parser.add_argument("--expected-mount", help="report when the mount differs from this path")
    parser.add_argument("--manifest", default=str(Path(__file__).with_name("manifest.json")))
    parser.add_argument("--apps-dir", default=os.path.expanduser("~/.local/share/applications"))
    parser.add_argument("--icons-dir", default=os.path.expanduser("~/.config/EmuDeck/backend/icons"))
    parser.add_argument("--backup-root", default=os.environ.get(
        "OMARCHY_BACKUP_ROOT", os.path.expanduser("~/.local/state/omarchy-gaming-setup/backups")))
    parser.add_argument("--findmnt", default="findmnt")
    parser.add_argument("--validator", default="desktop-file-validate")
    parser.add_argument("--update-desktop-database", default="update-desktop-database")
    args = parser.parse_args(argv)

    try:
        records = load_manifest(args.manifest)
    except (OSError, ValueError, ManifestError) as error:
        print(f"ERROR emulators: invalid manifest {args.manifest}: {error}", file=sys.stderr)
        return 2

    home = Path.home()
    mount, read_only = resolve_mount(args.uuid, args.findmnt)
    places = {"home": str(home), "icons": args.icons_dir}
    if mount is not None:
        places["emulation"] = os.path.join(mount, "Emulation")
        if args.expected_mount and mount != args.expected_mount:
            print(f"WARN emulators: GExtended is mounted at {mount}, expected {args.expected_mount}")
    plan = Plan(records, Path(args.apps_dir), places)

    if args.action == "dry-run":
        return dry_run(plan)
    if args.action == "check":
        return check(plan, args.validator, mount, read_only)
    return install(plan, args.validator, home, Path(args.backup_root),
                   args.update_desktop_database)


if __name__ == "__main__":
    sys.exit(main())
