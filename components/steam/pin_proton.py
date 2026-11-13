#!/usr/bin/env python3
"""Pin Steam games to a fixed Proton build instead of Proton Experimental.

Steam files Vulkan shader pre-caches under the Proton build a game runs on.
Proton Experimental updates about weekly, and an update that changes DXVK or
vkd3d-proton makes Steam download and replay the whole cache again (90k-200k
pipelines for Mortal Kombat 1 and Forza Horizon 5). A stable Proton changes
rarely, so the cache stays valid.

Steam rewrites config.vdf when it exits, so run this only with Steam closed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
from pathlib import Path
import shutil
import sys

# Reuse the line-preserving VDF editor from the Assetto Corsa component.
EDITOR_PATH = Path(__file__).resolve().parent.parent / "assetto-corsa" / "configure_steam.py"
SPEC = importlib.util.spec_from_file_location("configure_steam", EDITOR_PATH)
EDITOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EDITOR)

# Mortal Kombat 1, Forza Horizon 5
DEFAULT_APPIDS = ["1971870", "1551360"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--compat-tool", default="proton_11")
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("appids", nargs="*", default=DEFAULT_APPIDS)
    args = parser.parse_args()

    if not args.config.is_file():
        print(f"Missing Steam configuration: {args.config}", file=sys.stderr)
        return 2

    backup_dir = args.backup_dir / dt.datetime.now().strftime("%Y%m%d-%H%M%S-pin-proton")
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / args.config.name
    shutil.copy2(args.config, backup)

    changed = False
    for appid in args.appids:
        block = ["InstallConfigStore", *EDITOR.STEAM, "CompatToolMapping", appid]
        try:
            changed |= EDITOR.configure(
                args.config, block, {"name": args.compat_tool, "config": "", "priority": "250"}
            )
        except ValueError as error:
            print(f"{args.config}: {error}", file=sys.stderr)
            return 1

    if changed:
        print(f"Pinned {', '.join(args.appids)} to {args.compat_tool} (backup: {backup})")
    else:
        backup.unlink()
        backup_dir.rmdir()
        print(f"{', '.join(args.appids)} already use {args.compat_tool}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
