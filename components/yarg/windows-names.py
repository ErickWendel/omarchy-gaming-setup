#!/usr/bin/env python3
"""Renames song files and folders the Windows build of YARG can't open.

omarchy-yarg runs YARG's Windows build under Proton, and Windows programs
reject names with < > : " | ? * or ending in a dot or space (YARG logs
"Invalid name" / "Could not find a part of the path" and skips the song).
This replaces those characters with their full-width lookalikes
(< > : " | ? * -> ＜ ＞ ： ＂ ｜ ？ ＊) and drops trailing dots and spaces.
Deepest paths go first; a rename that would land on an existing name is
skipped and reported. Every rename is logged to restore it.

  windows-names.py [FOLDER...]           dry run
  windows-names.py --apply [FOLDER...]
  windows-names.py --restore             undo the logged renames
Without FOLDER, the song folders come from YARG's settings.json (the same
ones webm-videos.py uses).
"""
import argparse
import importlib.util
import os
import sys

MAP = str.maketrans('<>:"|?*', "＜＞：＂｜？＊")
LOG = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                   "omarchy-yarg", "windows-names.tsv")


def fixed(name):
    new = name.translate(MAP).rstrip(". ")
    return new or name.translate(MAP)


def song_folders():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "webm-videos.py")
    if not os.path.exists(path):  # installed as omarchy-yarg-videos
        path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "omarchy-yarg-videos")
    spec = importlib.util.spec_from_loader("webm_videos", importlib.machinery.SourceFileLoader("webm_videos", path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.song_folders()


def plan(roots):
    """(old, new) pairs, deepest first so parents are renamed last."""
    pairs = []
    for root in roots:
        for dp, dirs, files in os.walk(root):
            for n in dirs + files:
                if fixed(n) != n:
                    pairs.append((os.path.join(dp, n), os.path.join(dp, fixed(n))))
    pairs.sort(key=lambda p: p[0].count(os.sep), reverse=True)
    return pairs


def apply(pairs):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    done = skipped = 0
    with open(LOG, "a") as log:
        for old, new in pairs:
            if os.path.lexists(new):
                skipped += 1
                print(f"skipped (exists): {new}", file=sys.stderr)
                continue
            try:
                os.rename(old, new)
            except OSError as e:
                skipped += 1
                print(f"FAILED {old}: {e}", file=sys.stderr)
                continue
            log.write(f"{old}\t{new}\n")
            log.flush()
            done += 1
    return done, skipped


def restore():
    try:
        rows = [line.rstrip("\n").split("\t") for line in open(LOG)]
    except FileNotFoundError:
        print("nothing to restore")
        return 0
    failed = 0
    for old, new in reversed(rows):  # parents back first
        if os.path.lexists(old) or not os.path.lexists(new):
            failed += 1
            print(f"not restored: {new}", file=sys.stderr)
            continue
        os.rename(new, old)
    if not failed:
        os.replace(LOG, LOG + ".restored")
    print(f"restored {len(rows) - failed}, failed {failed}")
    return 1 if failed else 0


def main():
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(errors="backslashreplace", line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folders", nargs="*")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--restore", action="store_true")
    a = ap.parse_args()
    if a.restore:
        return restore()
    pairs = plan(a.folders or song_folders())
    if not a.apply:
        clashes = sum(os.path.lexists(n) for _o, n in pairs)
        print(f"would rename {len(pairs)} ({clashes} already exist and would be skipped)")
        for old, new in pairs:
            print(f"  {old}\n    -> {os.path.basename(new)}")
        return 0
    done, skipped = apply(pairs)
    print(f"renamed {done}, skipped {skipped}; log: {LOG}")
    return 1 if skipped else 0


if __name__ == "__main__":
    sys.exit(main())
