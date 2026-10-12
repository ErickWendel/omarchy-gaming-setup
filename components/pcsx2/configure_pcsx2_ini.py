#!/usr/bin/env python3
"""Apply the managed renderer and hotkey settings to PCSX2.ini.

PCSX2.ini repeats keys for multiple bindings, so it is edited line by line
instead of through configparser. Only the managed keys are touched.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile

# Steam's overlay hooks Vulkan in PCSX2 but not its OpenGL renderer.
GS_SETTINGS = {"Renderer": ["14"]}

# The PS button is forwarded to PCSX2 as Escape by the PS5 helper, and
# Share + Options opens the pause menu on whichever SDL slot the pad gets
# (a connected G29 wheel can take SDL-0).
HOTKEY_SETTINGS = {
    "OpenPauseMenu": ["Keyboard/Escape"]
    + [f"SDL-{slot}/Back & SDL-{slot}/Start" for slot in range(4)],
    "ShutdownVM": ["SDL-0/Back & SDL-0/RightStick"],
}

MANAGED = {"EmuCore/GS": GS_SETTINGS, "Hotkeys": HOTKEY_SETTINGS}


def configure(text: str) -> str:
    """Return ``text`` with every managed key set, keeping other lines intact.

    A managed key is written where its first binding already is; any further
    bindings for it are dropped. Missing keys go at the end of their section.
    """
    output: list[str] = []
    written: set[tuple[str, str]] = set()
    section = None

    def bindings(name, key):
        return [f"{key} = {value}" for value in MANAGED[name][key]]

    def finish(name):
        settings = MANAGED.get(name)
        if not settings:
            return
        missing = [key for key in settings if (name, key) not in written]
        if not missing:
            return
        # Keep the blank lines that separate sections after the new keys.
        tail = []
        while output and not output[-1].strip():
            tail.append(output.pop())
        for key in missing:
            output.extend(bindings(name, key))
            written.add((name, key))
        output.extend(reversed(tail))

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            finish(section)
            section = stripped[1:-1]
            output.append(line)
            continue
        if section in MANAGED and "=" in line:
            key = line.split("=", 1)[0].strip()
            if key in MANAGED[section]:
                if (section, key) not in written:
                    output.extend(bindings(section, key))
                    written.add((section, key))
                continue
        output.append(line)
    finish(section)

    for name, settings in MANAGED.items():
        if any((name, key) in written for key in settings):
            continue
        if output and output[-1].strip():
            output.append("")
        output.append(f"[{name}]")
        for key in settings:
            output.extend(bindings(name, key))

    return "\n".join(output) + "\n"


def pcsx2_running() -> bool:
    for cmdline in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            argv0 = cmdline.read_bytes().split(b"\0", 1)[0]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b"pcsx2" in os.path.basename(argv0).lower():
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--ini",
        type=Path,
        default=Path.home() / ".config/PCSX2/inis/PCSX2.ini",
    )
    args = parser.parse_args()

    if not args.ini.is_file():
        print(f"PCSX2.ini not found: {args.ini}; run PCSX2 once first.", file=sys.stderr)
        return 2
    if pcsx2_running():
        print("PCSX2 is running; close it before changing its settings.", file=sys.stderr)
        return 2

    original = args.ini.read_text(encoding="utf-8")
    updated = configure(original)
    if updated == original:
        print("PCSX2.ini is already current.")
        return 0

    fd, temporary = tempfile.mkstemp(prefix=".PCSX2.ini.", dir=args.ini.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(updated)
    os.replace(temporary, args.ini)
    print("PCSX2.ini: Vulkan renderer, PS/Escape and Share+Options pause menu")
    return 0


if __name__ == "__main__":
    sys.exit(main())
