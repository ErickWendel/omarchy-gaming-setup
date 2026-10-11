#!/usr/bin/env python3
"""Move PCSX2 Steam shortcuts to the canonical wrapper and disable Steam Input."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import os
from pathlib import Path
import shutil
import sys
import tempfile

import vdf


def steam_is_running() -> bool:
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text(encoding="utf-8").strip() == "steam":
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


def managed_entries(shortcuts: dict) -> list[dict]:
    return [
        entry
        for entry in shortcuts.get("shortcuts", {}).values()
        if "pcsx2" in str(entry.get("exe", "")).lower()
    ]


def configure(shortcuts: dict, localconfig: dict, wrapper: Path) -> list[tuple[int, str]]:
    changed: list[tuple[int, str]] = []
    apps = localconfig.setdefault("UserLocalConfigStore", {}).setdefault("apps", {})
    quoted_wrapper = f'"{wrapper}"'

    for entry in managed_entries(shortcuts):
        appid = int(entry["appid"]) & 0xFFFFFFFF
        entry["exe"] = quoted_wrapper
        entry["StartDir"] = str(wrapper.parent)
        app = apps.setdefault(str(appid), {})
        app["UseSteamControllerConfig"] = "0"
        changed.append((appid, str(entry.get("appname", appid))))

    return changed


def atomic_write(path: Path, writer) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, writer.mode) as stream:
            writer(stream)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


class BinaryWriter:
    mode = "wb"

    def __init__(self, data: dict):
        self.data = data

    def __call__(self, stream) -> None:
        vdf.binary_dump(self.data, stream)


class TextWriter:
    mode = "w"

    def __init__(self, data: dict):
        self.data = data

    def __call__(self, stream) -> None:
        vdf.dump(self.data, stream, pretty=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shortcuts", type=Path, required=True)
    parser.add_argument("--localconfig", type=Path, required=True)
    parser.add_argument("--wrapper", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if steam_is_running():
        print("Steam is running; exit Steam before changing its shortcuts.", file=sys.stderr)
        return 2
    for path in (args.shortcuts, args.localconfig):
        if not path.is_file():
            print(f"Missing Steam configuration: {path}", file=sys.stderr)
            return 2
    if not args.wrapper.is_file() or not os.access(args.wrapper, os.X_OK):
        print(f"Canonical wrapper is missing or not executable: {args.wrapper}", file=sys.stderr)
        return 2

    with args.shortcuts.open("rb") as stream:
        shortcuts = vdf.binary_load(stream)
    with args.localconfig.open(encoding="utf-8") as stream:
        localconfig = vdf.load(stream)

    original_shortcuts = copy.deepcopy(shortcuts)
    original_localconfig = copy.deepcopy(localconfig)
    changed = configure(shortcuts, localconfig, args.wrapper.resolve())
    if not changed:
        print("No PCSX2 Steam shortcuts were found.")
        return 0
    for appid, name in changed:
        print(f"{appid}: {name}: canonical wrapper + Steam Input disabled")
    if args.dry_run:
        return 0
    if shortcuts == original_shortcuts and localconfig == original_localconfig:
        print("Steam configuration is already current.")
        return 0

    backup_dir = args.backup_dir or (
        Path.home()
        / ".local/state/omarchy-gaming-setup/backups"
        / dt.datetime.now().strftime("%Y%m%d-%H%M%S-pcsx2")
    )
    backup_dir.mkdir(parents=True, exist_ok=False)
    shutil.copy2(args.shortcuts, backup_dir / args.shortcuts.name)
    shutil.copy2(args.localconfig, backup_dir / args.localconfig.name)

    atomic_write(args.shortcuts, BinaryWriter(shortcuts))
    atomic_write(args.localconfig, TextWriter(localconfig))
    print(f"Backup: {backup_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

