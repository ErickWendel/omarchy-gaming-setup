#!/usr/bin/env python3
"""Prefix managed Steam games' launch options with omarchy-match-resolution."""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import shutil
import sys
import tempfile

import vdf

COMPONENT_DIR = Path(__file__).resolve().parent
LOADER = importlib.machinery.SourceFileLoader(
    "match_resolution", str(COMPONENT_DIR / "match-resolution")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MATCH_RESOLUTION = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MATCH_RESOLUTION
LOADER.exec_module(MATCH_RESOLUTION)


def with_wrapper(options: str, wrapper: str) -> str:
    """Return launch options that run ``wrapper`` before the game command."""
    if wrapper in options:
        return options
    options = options.strip()
    if "%command%" in options:
        return options.replace("%command%", f"{wrapper} %command%", 1)
    # Options without %command% are arguments for the game itself.
    return f"{wrapper} %command% {options}".rstrip()


def configure(localconfig: dict, wrapper: str, appids) -> list[str]:
    apps = (
        localconfig.setdefault("UserLocalConfigStore", {})
        .setdefault("Software", {})
        .setdefault("Valve", {})
        .setdefault("Steam", {})
        .setdefault("apps", {})
    )
    changed = []
    for appid in appids:
        app = apps.setdefault(appid, {})
        current = app.get("LaunchOptions", "")
        updated = with_wrapper(current, wrapper)
        if updated != current:
            app["LaunchOptions"] = updated
            changed.append(appid)
    return changed


def steam_is_running() -> bool:
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text(encoding="utf-8").strip() == "steam":
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--localconfig", type=Path, required=True)
    parser.add_argument("--wrapper", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path)
    args = parser.parse_args()

    if steam_is_running():
        print("Steam is running; exit Steam before changing launch options.", file=sys.stderr)
        return 2
    if not args.localconfig.is_file():
        print(f"Missing Steam configuration: {args.localconfig}", file=sys.stderr)
        return 2

    with args.localconfig.open(encoding="utf-8") as stream:
        localconfig = vdf.load(stream)
    changed = configure(localconfig, str(args.wrapper), MATCH_RESOLUTION.GAMES)
    if not changed:
        print("Steam launch options are already current.")
        return 0

    backup_dir = args.backup_dir or (
        Path.home()
        / ".local/state/omarchy-gaming-setup/backups"
        / dt.datetime.now().strftime("%Y%m%d-%H%M%S-launch-options")
    )
    backup_dir.mkdir(parents=True, exist_ok=False)
    shutil.copy2(args.localconfig, backup_dir / args.localconfig.name)

    fd, temporary = tempfile.mkstemp(prefix=".localconfig.vdf.", dir=args.localconfig.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        vdf.dump(localconfig, stream, pretty=True)
    os.replace(temporary, args.localconfig)
    for appid in changed:
        name = MATCH_RESOLUTION.GAMES[appid].name
        print(f"{appid}: {name}: launch options run {args.wrapper.name}")
    print(f"Backup: {backup_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
