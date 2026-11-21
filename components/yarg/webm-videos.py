#!/usr/bin/env python3
"""Makes song videos play, in sync, in YARG on Linux.

1. Format. YARG plays song videos through libVLC 4, which Arch does not
   ship (it has VLC 3), and falls back to Unity's VideoPlayer, which on Linux
   decodes VP8 WebM only. So H.264 video.mp4 files (Clone Hero charts,
   BackstageHero downloads) show the venue. YARG picks a song's video by name
   first, then extension (bg, background, video x .mp4 .mov .webm .mkv; see
   YARG.Core SongEntry.UnpackedIni), so for each song whose picked video is
   not VP8 this writes a VP8 bg.webm, which then wins. The original stays.

2. Offsets. BackstageHero writes video_start_time = -L*1000 when the song
   starts L s into the video (skip L s); YARG reads a negative start time as
   "delay the video" and a positive one as "skip into it" (BackgroundManager).
   For songs BackstageHero synced (backstagehero_source in song.ini) the value
   is negated for YARG and BackstageHero's own value kept as
   omarchy_bh_video_start_time. --offsets backstagehero puts its values back
   (before BackstageHero runs, so its sync editor stays right).

  webm-videos.py [--jobs N] [--dry-run] [--no-video] FOLDER...
  webm-videos.py --offsets backstagehero
  webm-videos.py --remove-copies [--dry-run] [FOLDER...]
Without FOLDER, the song folders come from YARG's settings.json.
"""
import argparse
import concurrent.futures
import glob
import json
import os
import re
import subprocess
import sys

NAMES = ("bg", "background", "video")
EXTS = (".mp4", ".mov", ".webm", ".mkv")
# Bump when the encoding changes; bg.webm files we made with an older tag are
# encoded again.
TAG = "omarchy-webm-v2"
BH_KEY = "omarchy_bh_video_start_time"
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                     "omarchy-yarg", "bh-offsets.txt")
DATA = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
# Linux YARG, and the Windows build omarchy-yarg runs in its Wine prefix.
SETTINGS = sorted(glob.glob(os.path.expanduser("~/.config/unity3d/YARC/YARG/*/settings.json"))) + sorted(
    glob.glob(os.path.join(DATA, "omarchy-yarg/proton/pfx/drive_c/users/steamuser/AppData/LocalLow"
                           "/YARC/YARG/*/settings.json")))


def song_folders():
    folders = []
    for path in SETTINGS:
        try:
            for f in json.load(open(path)).get("SongFolders", []):
                if f[:3].upper() == "Z:\\":  # Wine path
                    f = f[2:].replace("\\", "/")
                if f not in folders and os.path.isdir(f):
                    folders.append(f)
        except (OSError, ValueError):
            pass
    return folders


def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                        "stream=codec_name,bit_rate,height:format=bit_rate:format_tags=comment",
                        "-of", "json", path], capture_output=True, text=True, errors="replace")
    try:
        d = json.loads(r.stdout or "{}")
    except ValueError:
        d = {}
    s = (d.get("streams") or [{}])[0]
    fmt = d.get("format") or {}
    rate = s.get("bit_rate") or fmt.get("bit_rate") or 0
    return {"codec": s.get("codec_name", ""), "height": int(s.get("height") or 0),
            "bitrate": int(rate),
            "tag": {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}.get("comment", "")}


def candidates(files):
    """Videos in YARG's order of preference."""
    low = {f.lower(): f for f in files}
    return [low[s + e] for s in NAMES for e in EXTS if s + e in low]


def video_job(folder, files):
    """The source to encode into bg.webm, or None when YARG can play it."""
    vids = candidates(files)
    if not vids:
        return None
    pick = vids[0]
    info = probe(os.path.join(folder, pick))
    if pick.lower() == "bg.webm" and info["tag"] != TAG:
        # Ours from an older run (tagged, or untagged from the first version,
        # which sits next to the video it came from): encode again.
        rest = [v for v in vids[1:] if probe(os.path.join(folder, v))["codec"] != "vp8"]
        if rest and (info["tag"].startswith("omarchy-webm") or not info["tag"]):
            return os.path.join(folder, rest[0])
    if info["codec"] == "vp8":
        return None
    if pick.lower() in ("bg.mp4", "bg.mov"):
        print(f"skipped (bg.webm would lose to {pick}): {folder}", file=sys.stderr)
        return None
    return os.path.join(folder, pick)


def our_copy(folder, files):
    """bg.webm this tool made (tagged omarchy-webm*) next to the video it came
    from, else None. Untagged or lone bg.webm files are never ours to delete."""
    low = {f.lower(): f for f in files}
    if "bg.webm" not in low:
        return None
    if not [v for v in candidates(files) if v.lower() != "bg.webm"]:
        return None
    path = os.path.join(folder, low["bg.webm"])
    return path if probe(path)["tag"].startswith("omarchy-webm") else None


def remove_copies(roots, dry_run):
    """Delete our VP8 copies; the Windows build plays the originals."""
    found, size, failed = [], 0, 0
    for folder, files, _ini in scan(roots):
        path = our_copy(folder, files)
        if not path:
            continue
        found.append(path)
        size += os.path.getsize(path)
        if dry_run:
            continue
        try:
            with writable(folder):
                os.remove(path)
        except OSError as e:
            failed += 1
            print(f"FAILED {path}: {e}", file=sys.stderr)
    verb = "would remove" if dry_run else "removed"
    print(f"{verb} {len(found) - failed} bg.webm copies ({size / 1e9:.1f} GB)")
    for path in found[:20] if dry_run else []:
        print(f"  {path}")
    return 1 if failed else 0


def writable(path):
    """Context: briefly add owner write to a read-only folder or file."""
    class Ctx:
        def __enter__(self):
            self.mode = os.stat(path).st_mode
            self.changed = not os.access(path, os.W_OK)
            if self.changed:
                os.chmod(path, self.mode | 0o200)

        def __exit__(self, *exc):
            if self.changed:
                os.chmod(path, self.mode)
    return Ctx()


def encode(src):
    folder = os.path.dirname(src)
    dest, part = os.path.join(folder, "bg.webm"), os.path.join(folder, ".bg.webm.part")
    info = probe(src)
    # VP8 needs well over H.264's bitrate for the same picture.
    rate = min(max(int(info["bitrate"] * 2.5), 2_000_000), 8_000_000)
    try:
        with writable(folder):
            r = subprocess.run(
                ["nice", "-n", "15", "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                 "-i", src, "-map", "0:v:0", "-an", "-sn", "-vf", "scale=-2:'min(1080,ih)'",
                 "-c:v", "libvpx", "-deadline", "good", "-cpu-used", "2", "-threads", "4",
                 "-crf", "4", "-b:v", str(rate), "-qmin", "0", "-qmax", "40",
                 "-auto-alt-ref", "1", "-lag-in-frames", "16",
                 "-metadata", f"comment={TAG}", "-f", "webm", part],
                capture_output=True, text=True, errors="replace")
            if r.returncode != 0 or not os.path.getsize(part):
                lines = r.stderr.strip().splitlines()
                raise RuntimeError(lines[-1] if lines else "ffmpeg failed")
            os.replace(part, dest)
        return src, None
    except Exception as e:  # report and go on with the next song
        try:
            with writable(folder):
                os.unlink(part)
        except OSError:
            pass
        return src, str(e)


VST = re.compile(r"(?im)^(video_start_time[ \t]*=[ \t]*)(-?\d+)[ \t]*$")
BHV = re.compile(rf"(?im)^{BH_KEY}[ \t]*=[ \t]*(-?\d+)[ \t]*\n?")


def read(path):
    return open(path, encoding="utf-8", errors="surrogateescape").read()


def write(path, text):
    with writable(os.path.dirname(path)), writable(path):
        tmp = path + ".omarchy-tmp"
        with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(text)
        os.chmod(tmp, os.stat(path).st_mode)
        os.replace(tmp, path)


def to_yarg(ini):
    """Negate BackstageHero's offset once; True when the file changed."""
    text = read(ini)
    if "backstagehero_source" not in text:
        return False
    m = VST.search(text)
    if not m:
        return False
    cur = int(m.group(2))
    saved = BHV.search(text)
    if saved and int(saved.group(1)) == -cur:
        return False  # already in YARG's meaning
    # Not converted yet, or BackstageHero wrote a new value since.
    text = BHV.sub("", text)
    m = VST.search(text)
    text = text[:m.start()] + f"{m.group(1)}{-cur}\n{BH_KEY} = {cur}" + text[m.end():]
    write(ini, text)
    return True


def to_backstagehero(ini):
    text = read(ini)
    saved, m = BHV.search(text), VST.search(text)
    if not saved:
        return False
    text = BHV.sub("", text)
    m = VST.search(text)
    if m:
        text = text[:m.start()] + f"{m.group(1)}{saved.group(1)}" + text[m.end():]
    write(ini, text)
    return True


def remember(inis):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    known = set(open(STATE, encoding="utf-8", errors="surrogateescape").read().splitlines()) \
        if os.path.exists(STATE) else set()
    with open(STATE, "a", encoding="utf-8", errors="surrogateescape") as f:
        for ini in inis:
            if ini not in known:
                f.write(ini + "\n")


def restore_backstagehero():
    if not os.path.exists(STATE):
        return 0
    n = 0
    for ini in open(STATE, encoding="utf-8", errors="surrogateescape").read().splitlines():
        try:
            n += to_backstagehero(ini)
        except OSError:
            pass
    os.remove(STATE)
    return n


def scan(roots):
    for root in roots:
        for dp, _dirs, files in os.walk(root):
            ini = next((f for f in files if f.lower() == "song.ini"), None)
            if ini:
                yield dp, files, os.path.join(dp, ini)


def main():
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(errors="backslashreplace", line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folders", nargs="*")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-video", action="store_true", help="only fix offsets")
    ap.add_argument("--offsets", choices=("yarg", "backstagehero"), default="yarg")
    ap.add_argument("--remove-copies", action="store_true",
                    help="delete the bg.webm copies this tool made (the Windows build plays the originals)")
    a = ap.parse_args()
    if a.remove_copies:
        return remove_copies(a.folders or song_folders(), a.dry_run)
    if a.offsets == "backstagehero":
        print(f"restored BackstageHero offsets in {restore_backstagehero()} songs")
        return 0
    roots = a.folders or song_folders()
    flipped, jobs = [], []
    for folder, files, ini in scan(roots):
        try:
            if not a.dry_run and to_yarg(ini):
                flipped.append(ini)
            elif "backstagehero_source" in read(ini) and BH_KEY in read(ini):
                flipped.append(ini)
        except OSError as e:
            print(f"offset not changed in {ini}: {e}", file=sys.stderr)
        if not a.no_video:
            src = video_job(folder, files)
            if src:
                jobs.append(src)
    if not a.dry_run:
        remember(flipped)
    print(f"{len(flipped)} BackstageHero offsets in YARG's meaning; {len(jobs)} videos to encode")
    if a.dry_run or not jobs:
        for src in jobs[:20]:
            print(f"  {src}")
        return 0
    done = failed = 0
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as pool:
        for src, err in pool.map(encode, jobs):
            if err:
                failed += 1
                print(f"FAILED {src}: {err}", file=sys.stderr)
            else:
                done += 1
                print(f"[{done + failed}/{len(jobs)}] {src}")
    print(f"encoded {done}, failed {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
