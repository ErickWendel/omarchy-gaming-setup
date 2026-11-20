#!/usr/bin/env python3
"""Moves duplicate song charts out of the YARG song folders.

Songs are the same when their artist and title match after normalizing
(case, accents, punctuation, "&"/"and", a leading "The"). Of each group the
most complete chart stays: charted parts first, then vocals/harmonies, pro
parts, separate stems, a .mid chart, a video and album art; ties go to the
Ultimate REpack. The others are moved (never deleted) to --dest, keeping
their path below --base, and listed in <dest>/moved.tsv so --restore can put
them back.

  dedupe-songs.py [--apply] FOLDER...     dry run unless --apply
  dedupe-songs.py --restore               move everything in moved.tsv back
"""
import argparse
import collections
import os
import re
import sys
import unicodedata

BASE = "/wdblack_4TB/Games"
DEST = "/wdblack_4TB/Games/CloneHero-Duplicates"
INSTR = ["guitar", "bass", "rhythm", "guitar_coop", "drums", "drums_real", "keys", "keys_real",
         "vocals", "vocals_harm", "pro_drums", "guitarghl", "bassghl", "real_guitar", "real_bass", "band"]
AUDIO = (".ogg", ".opus", ".mp3", ".wav", ".flac", ".mogg")
VIDEO = (".mp4", ".webm", ".avi", ".mkv")
PREFERRED = "Songs-UltimateREpack"
TAG = re.compile(r"<[^>]*>")


def read_ini(path):
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-16"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            pass
    else:
        text = raw.decode("latin-1")
    d = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d[k.strip().lower()] = v.strip()
    return d


def scan(roots):
    for root in roots:
        for dp, _dirs, files in os.walk(root):
            low = {f.lower() for f in files}
            if "song.ini" not in low:
                continue
            ini = next(f for f in files if f.lower() == "song.ini")
            try:
                d = read_ini(os.path.join(dp, ini))
            except OSError:
                continue
            parts = set()
            for i in INSTR:
                try:
                    if int(float(d.get("diff_" + i, ""))) >= 0:
                        parts.add(i)
                except ValueError:
                    pass
            yield {
                "dir": dp, "artist": d.get("artist", ""), "name": d.get("name", ""), "parts": parts,
                "stems": sum(1 for f in low if f.endswith(AUDIO) and not f.startswith("preview")),
                "mid": "notes.mid" in low,
                "video": any(f.startswith(("video.", "bg.")) and f.endswith(VIDEO) for f in low),
                "art": any(f.startswith("album.") for f in low),
                "pro_drums": d.get("pro_drums", "").lower() in ("true", "1"),
            }


def norm(s):
    s = unicodedata.normalize("NFKD", TAG.sub("", s)).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"^the\s+", "", s.replace("&", " and ").strip())
    return re.sub(r"[^a-z0-9]+", "", s)


def score(r):
    p = r["parts"]
    five = sum(i in p for i in ("guitar", "bass", "rhythm", "drums", "keys"))
    pro = sum(i in p for i in ("drums_real", "keys_real", "real_guitar", "real_bass", "pro_drums")) + r["pro_drums"]
    vox = ("vocals" in p) + ("vocals_harm" in p)
    return five * 10 + vox * 8 + pro * 3 + min(r["stems"], 8) * 2 + r["mid"] * 2 + r["video"] * 2 + r["art"]


def rank(r):
    return (score(r), PREFERRED in r["dir"], -len(r["dir"]), r["dir"])


def plan(songs):
    groups = collections.defaultdict(list)
    for r in songs:
        key = (norm(r["artist"]), norm(r["name"]))
        if key[1]:
            groups[key].append(r)
    all_dirs = sorted(r["dir"] for r in songs)
    moves = []
    for group in groups.values():
        if len(group) < 2:
            continue
        group.sort(key=rank, reverse=True)
        for r in group[1:]:
            # A song folder holding other song folders would take them along.
            prefix = r["dir"] + os.sep
            if any(d.startswith(prefix) for d in all_dirs):
                continue
            moves.append((r["dir"], group[0]["dir"]))
    return moves


def safe_target(src, base, dest):
    rel = os.path.relpath(src, base)
    if rel.startswith("..") or rel in (".", ""):
        raise ValueError(f"{src} is not below {base}")
    return os.path.join(dest, rel)


def apply(moves, base, dest):
    os.makedirs(dest, exist_ok=True)
    moved = 0
    with open(os.path.join(dest, "moved.tsv"), "a", encoding="utf-8", errors="surrogateescape") as log:
        for src, kept in moves:
            target = safe_target(src, base, dest)
            if not os.path.isdir(src) or os.path.lexists(target):
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            try:
                move_dir(src, target)
            except OSError as e:
                print(f"skipped {src}: {e.strerror}", file=sys.stderr)
                continue
            log.write(f"{src}\t{target}\t{kept}\n")
            log.flush()
            moved += 1
    return moved


def move_dir(src, target):
    """Renames, briefly adding owner write to both parents and the folder
    itself when an archive left them read-only (moving a folder rewrites its
    ".." entry); the original modes are put back."""
    try:
        os.rename(src, target)
        return
    except PermissionError:
        pass
    parents = {os.path.dirname(src), os.path.dirname(target)}
    modes = {p: os.stat(p).st_mode for p in parents}
    src_mode = os.stat(src).st_mode
    try:
        for p, m in modes.items():
            os.chmod(p, m | 0o200)
        os.chmod(src, src_mode | 0o200)
        os.rename(src, target)
    finally:
        os.chmod(target if os.path.isdir(target) else src, src_mode)
        for p, m in modes.items():
            os.chmod(p, m)


def restore(dest):
    path = os.path.join(dest, "moved.tsv")
    back = 0
    for line in open(path, encoding="utf-8", errors="surrogateescape"):
        src, target, _kept = line.rstrip("\n").split("\t")
        if os.path.isdir(target) and not os.path.lexists(src):
            os.makedirs(os.path.dirname(src), exist_ok=True)
            move_dir(target, src)
            back += 1
    os.rename(path, path + ".restored")
    return back


def main():
    sys.stdout.reconfigure(errors="backslashreplace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folders", nargs="*")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--restore", action="store_true")
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--dest", default=DEST)
    a = ap.parse_args()
    base, dest = os.path.abspath(a.base), os.path.abspath(a.dest)
    if a.restore:
        print(f"restored {restore(dest)} folders")
        return
    if not a.folders:
        ap.error("give the song folders to dedupe")
    for f in a.folders:
        f = os.path.abspath(f)
        if f == dest or f.startswith(dest + os.sep) or dest.startswith(f + os.sep):
            ap.error(f"{f} overlaps {dest}")
        safe_target(os.path.abspath(f) + "/x", base, dest)
    songs = list(scan(a.folders))
    moves = plan(songs)
    print(f"{len(songs)} charts, {len(moves)} duplicates to move to {dest}")
    if not a.apply:
        for src, kept in moves[:20]:
            print(f"  {src}\n    kept: {kept}")
        print("dry run; add --apply to move them")
        return
    print(f"moved {apply(moves, base, dest)} folders; list in {dest}/moved.tsv")


if __name__ == "__main__":
    sys.exit(main())
