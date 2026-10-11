#!/usr/bin/env python3
"""Disable OpenRGB's internal XDG autostart without starting device discovery."""

from __future__ import annotations

import argparse
import json
import os
import stat
import tempfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    args = parser.parse_args()
    config: Path = args.config

    if not config.exists():
        return 0

    with config.open(encoding="utf-8") as source:
        data = json.load(source)
    if not isinstance(data, dict):
        raise ValueError(f"OpenRGB config must contain a JSON object: {config}")

    autostart = data.get("AutoStart")
    if autostart is None:
        autostart = {}
        data["AutoStart"] = autostart
    if not isinstance(autostart, dict):
        raise ValueError(f"OpenRGB AutoStart setting must be a JSON object: {config}")
    if autostart.get("enabled") is False:
        return 0
    autostart["enabled"] = False

    mode = stat.S_IMODE(config.stat().st_mode)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=config.parent, prefix=f".{config.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
            json.dump(data, destination, indent=4, ensure_ascii=False)
            destination.write("\n")
            destination.flush()
            os.fsync(destination.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, config)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
