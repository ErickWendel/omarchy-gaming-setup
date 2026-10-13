#!/usr/bin/env python3
"""Set Assetto Corsa's Steam launch options and compatibility tool.

Steam rewrites both files when it exits, so run this only with Steam closed.
The files are edited in place line by line: a full VDF parse and dump is not
lossless (multi-line values such as SDL_GamepadBind get re-escaped).
Both files are backed up before they are replaced.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

LONE_KEY = re.compile(r'^\s*"([^"]*)"\s*$')


def quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def set_value(lines: list[str], path: list[str], key: str, value: str) -> bool:
    """Set ``key`` inside the block at ``path``, creating missing blocks.

    ``path`` is matched as a suffix of the current block path, case-insensitively,
    so ``["apps", "244210"]`` finds the app wherever its ``apps`` block lives.
    """
    want = [p.lower() for p in path]
    stack: list[str] = []
    pending = None
    deepest = (-1, 0)  # (matched depth, line index of that block's closing brace)
    open_at: dict[int, int] = {}
    line_re = re.compile(r'^(\s*)"' + re.escape(key) + r'"(\s+)"(?:[^"\\]|\\.)*"\s*$', re.IGNORECASE)
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "{":
            stack.append((pending or "").lower())
            open_at[len(stack)] = index
            pending = None
            continue
        if stripped == "}":
            matched = matched_depth(stack, want)
            if matched > deepest[0]:
                deepest = (matched, index)
            if matched == len(want):
                indent = re.match(r"\s*", line).group(0) + "\t"
                lines.insert(index, f"{indent}{quote(key)}\t\t{quote(value)}\n")
                return True
            stack.pop()
            continue
        found = LONE_KEY.match(line)
        pending = found.group(1) if found else None
        if matched_depth(stack, want) == len(want):
            hit = line_re.match(line)
            if hit:
                updated = f"{hit.group(1)}{quote(key)}{hit.group(2)}{quote(value)}\n"
                if line == updated:
                    return False
                lines[index] = updated
                return True
    raise ValueError(f"block {'/'.join(path[:max(deepest[0], 0)])} not found")


def matched_depth(stack: list[str], want: list[str]) -> int:
    """Return how much of ``want`` the innermost blocks of ``stack`` match."""
    for size in range(min(len(want), len(stack)), 0, -1):
        if stack[-size:] == want[:size]:
            return size
    return 0


def ensure_block(lines: list[str], parent: list[str], name: str) -> None:
    """Create an empty ``name`` block inside ``parent`` if it does not exist."""
    want = [p.lower() for p in parent]
    stack: list[str] = []
    pending = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "{":
            stack.append((pending or "").lower())
            pending = None
            if stack[-len(want) - 1:] == want + [name.lower()]:
                return
            continue
        if stripped == "}":
            if stack[-len(want):] == want:
                indent = re.match(r"\s*", line).group(0) + "\t"
                lines[index:index] = [f"{indent}{quote(name)}\n", f"{indent}{{\n", f"{indent}}}\n"]
                return
            stack.pop()
            continue
        found = LONE_KEY.match(line)
        pending = found.group(1) if found else None
    raise ValueError(f"block {'/'.join(parent)} not found")


def configure(path: Path, block: list[str], values: dict[str, str]) -> bool:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    ensure_block(lines, block[:-1], block[-1])
    changed = False
    for key, value in values.items():
        changed |= set_value(lines, block, key, value)
    if changed:
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.writelines(lines)
        os.replace(temporary, path)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--localconfig", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--appid", default="244210")
    parser.add_argument("--launch-options", required=True)
    parser.add_argument("--compat-tool", required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    args = parser.parse_args()

    for path in (args.localconfig, args.config):
        if not path.is_file():
            print(f"Missing Steam configuration: {path}", file=sys.stderr)
            return 2

    backup_dir = args.backup_dir / dt.datetime.now().strftime("%Y%m%d-%H%M%S-assetto-corsa")
    edits = [
        (args.localconfig, ["apps", args.appid], {"LaunchOptions": args.launch_options}),
        (args.config, ["CompatToolMapping", args.appid],
         {"name": args.compat_tool, "config": "", "priority": "250"}),
    ]
    for path, block, values in edits:
        backup = backup_dir / path.name
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, backup)
        try:
            changed = configure(path, block, values)
        except ValueError as error:
            print(f"{path}: {error}", file=sys.stderr)
            return 1
        if changed:
            print(f"Updated {path} (backup: {backup})")
        else:
            backup.unlink()
            print(f"{path.name} is already current")
    if backup_dir.is_dir() and not any(backup_dir.iterdir()):
        backup_dir.rmdir()
    return 0


if __name__ == "__main__":
    sys.exit(main())
