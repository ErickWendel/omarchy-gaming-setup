#!/usr/bin/env python3
"""Add the YARG non-Steam shortcut (native, no Proton) pointing at omarchy-yarg.

Steam rewrites shortcuts.vdf when it exits, so run this only with Steam
closed. Reuses the NFS Most Wanted shortcut helpers; the file is backed up
before it changes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import os
from pathlib import Path
import shutil
import sys
import tempfile

import vdf

helper_path = Path(__file__).resolve().parent.parent / "nfsmw" / "configure_steam.py"
spec = importlib.util.spec_from_file_location("nfsmw_configure_steam", helper_path)
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shortcuts", type=Path, required=True)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--name", default="YARG")
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--icon", default="", help="icon file for the shortcut (grid/<appid>_icon.png)")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--print-appid", action="store_true")
    args = parser.parse_args()

    exe = f'"{args.exe}"'
    shortcuts = {}
    if args.shortcuts.is_file():
        with args.shortcuts.open("rb") as stream:
            shortcuts = vdf.binary_load(stream)
    entry = helpers.find_shortcut(shortcuts, exe, args.name)
    if args.print_appid:
        appid = entry["appid"] & 0xFFFFFFFF if entry else helpers.shortcut_appid(exe, args.name)
        print(appid)
        return 0
    if args.check:
        return 0 if entry is not None and entry.get("exe") == exe else 1

    changed = helpers.add_shortcut(shortcuts, exe, args.name, f"{args.exe.parent}/")
    entry = helpers.find_shortcut(shortcuts, exe, args.name)
    if args.icon and entry.get("icon") != args.icon:
        entry["icon"] = args.icon
        changed = True
    if not changed:
        print(f"Shortcut {args.name} already up to date")
        return 0
    if args.shortcuts.is_file():
        backup_dir = args.backup_dir / dt.datetime.now().strftime("%Y%m%d-%H%M%S-yarg")
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.shortcuts, backup_dir / args.shortcuts.name)
        print(f"Backup: {backup_dir}")
    fd, temporary = tempfile.mkstemp(prefix=f".{args.shortcuts.name}.", dir=args.shortcuts.parent)
    with os.fdopen(fd, "wb") as stream:
        vdf.binary_dump(shortcuts, stream)
    os.replace(temporary, args.shortcuts)
    entry = helpers.find_shortcut(shortcuts, exe, args.name)
    print(f"Shortcut {args.name} ({entry['appid'] & 0xFFFFFFFF}) written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
