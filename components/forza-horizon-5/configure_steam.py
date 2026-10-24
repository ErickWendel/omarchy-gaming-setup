#!/usr/bin/env python3
"""Add or remove the rev-light wrapper in Forza Horizon 5's Steam launch options.

The wrapper goes right before %command%, so whatever already precedes the
game (environment, omarchy-match-resolution) keeps running first. Steam must
be closed: it rewrites localconfig.vdf on exit.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
from pathlib import Path
import shutil
import sys
import tempfile

import vdf


def with_wrapper(options: str, wrapper: str) -> str:
    if wrapper in options.split():
        return options
    options = options.strip()
    if "%command%" in options:
        return options.replace("%command%", f"{wrapper} %command%", 1)
    # Options without %command% are arguments for the game itself.
    return f"{wrapper} %command% {options}".rstrip()


def without_wrapper(options: str, wrapper: str) -> str:
    return " ".join(word for word in options.split(" ") if word != wrapper).strip()


def app_block(localconfig: dict, appid: str) -> dict:
    return (
        localconfig.setdefault("UserLocalConfigStore", {})
        .setdefault("Software", {})
        .setdefault("Valve", {})
        .setdefault("Steam", {})
        .setdefault("apps", {})
        .setdefault(appid, {})
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--localconfig", type=Path, required=True)
    parser.add_argument("--appid", default="1551360")
    parser.add_argument("--wrapper", required=True)
    parser.add_argument("--remove", action="store_true")
    parser.add_argument("--backup-dir", type=Path, required=True)
    args = parser.parse_args()

    with args.localconfig.open(encoding="utf-8") as stream:
        localconfig = vdf.load(stream)
    app = app_block(localconfig, args.appid)
    current = app.get("LaunchOptions", "")
    change = without_wrapper if args.remove else with_wrapper
    updated = change(current, args.wrapper)
    if updated == current:
        print("Steam launch options are already current.")
        return 0

    backup = args.backup_dir / dt.datetime.now().strftime("%Y%m%d-%H%M%S-forza-horizon-5")
    backup.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.localconfig, backup / args.localconfig.name)
    app["LaunchOptions"] = updated
    fd, temporary = tempfile.mkstemp(prefix=".localconfig.vdf.", dir=args.localconfig.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        vdf.dump(localconfig, stream, pretty=True)
    os.replace(temporary, args.localconfig)
    print(f"Steam launch options: {updated}")
    print(f"Backup: {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
