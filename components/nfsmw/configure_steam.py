#!/usr/bin/env python3
"""Add the NFS Most Wanted non-Steam shortcut, with the wheel wrapper as its
launch option, and pin its Proton.

Steam rewrites both files when it exits, so run this only with Steam closed.
shortcuts.vdf is binary and round-trips through the vdf module; config.vdf
is edited line by line with the Assetto Corsa helper. Changed files are backed
up first.
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import os
import zlib

import vdf

STEAM = ["Software", "Valve", "Steam"]
helper_path = Path(__file__).resolve().parent.parent / "assetto-corsa" / "configure_steam.py"
spec = importlib.util.spec_from_file_location("assetto_configure_steam", helper_path)
text_vdf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(text_vdf)


def shortcut_appid(exe: str, name: str) -> int:
    """The appid Steam gives a shortcut it creates itself."""
    return (zlib.crc32((exe + name).encode()) & 0xFFFFFFFF) | 0x80000000


def signed(appid: int) -> int:
    return appid - (1 << 32) if appid >= 1 << 31 else appid


def set_launch_options(entry: dict, options: str) -> bool:
    """Set the wrapper launch option unless the user has their own."""
    current = entry.get("LaunchOptions", "")
    if current == options:
        return False
    if current and "nfsmw-wheel-wrapper" not in current:
        print(f"Keeping custom launch options: {current}", file=sys.stderr)
        return False
    entry["LaunchOptions"] = options
    return True


def add_shortcut(shortcuts: dict, exe: str, name: str, start_dir: str, options: str = "") -> bool:
    entries = shortcuts.setdefault("shortcuts", {})
    for entry in entries.values():
        if entry.get("exe") == exe:
            return set_launch_options(entry, options) if options else False
    index = str(max((int(k) for k in entries), default=-1) + 1)
    entries[index] = {
        "appid": signed(shortcut_appid(exe, name)),
        "appname": name,
        "exe": exe,
        "StartDir": start_dir,
        "icon": "",
        "ShortcutPath": "",
        "LaunchOptions": options,
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
        "tags": {},
    }
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shortcuts", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--compat-tool", required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--launch-options", default="")
    parser.add_argument("--print-appid", action="store_true")
    args = parser.parse_args()

    exe = f'"{args.exe}"'
    appid = shortcut_appid(exe, args.name)
    if args.print_appid:
        print(appid)
        return 0
    for path in (args.shortcuts, args.config):
        if not path.is_file():
            print(f"Missing Steam configuration: {path}", file=sys.stderr)
            return 2

    backup_dir = args.backup_dir / dt.datetime.now().strftime("%Y%m%d-%H%M%S-nfsmw")
    backup_dir.mkdir(parents=True, exist_ok=True)

    with args.shortcuts.open("rb") as stream:
        shortcuts = vdf.binary_load(stream)
    if add_shortcut(shortcuts, exe, args.name, f"{args.exe.parent}/", args.launch_options):
        shutil.copy2(args.shortcuts, backup_dir / args.shortcuts.name)
        fd, temporary = tempfile.mkstemp(prefix=f".{args.shortcuts.name}.", dir=args.shortcuts.parent)
        with os.fdopen(fd, "wb") as stream:
            vdf.binary_dump(shortcuts, stream)
        os.replace(temporary, args.shortcuts)
        print(f"Shortcut {args.name} ({appid}) written")
    else:
        print(f"Shortcut for {args.exe.name} already up to date")

    shutil.copy2(args.config, backup_dir / args.config.name)
    block = ["InstallConfigStore", *STEAM, "CompatToolMapping", str(appid)]
    try:
        changed = text_vdf.configure(args.config, block,
                                     {"name": args.compat_tool, "config": "", "priority": "250"})
    except ValueError as error:
        print(f"{args.config}: {error}", file=sys.stderr)
        return 1
    if changed:
        print(f"Compatibility tool {args.compat_tool} set")
    else:
        (backup_dir / args.config.name).unlink()
        print("Compatibility tool already set")
    if not any(backup_dir.iterdir()):
        backup_dir.rmdir()
    else:
        print(f"Backup: {backup_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
