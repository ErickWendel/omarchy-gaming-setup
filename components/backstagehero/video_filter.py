#!/usr/bin/env python3
"""Keep BackstageHero from picking still-image "videos" for songs.

BackstageHero searches YouTube for "artist title", sorts the results by length
only, and takes the first one whose audio matches the chart. The uploads
whose audio matches best are often the ones with nothing to watch: "Official
Audio" uploads, "Provided to YouTube by ..." art tracks from "- Topic"
channels, full-album streams, lyric slideshows. This module is loaded into
BackstageHero by omarchy-bh-run (components/backstagehero) and changes two
steps there:

- Search: pulls more results, drops audio-only uploads by title, channel and
  description, and puts official videos, music videos and live performances
  first. If nothing is left it searches again with "official video" added.
- Download: samples frames of the downloaded video with ffmpeg. A video whose
  picture barely changes (a cover, a few stills) is thrown away, the previous
  video if any is put back, and BackstageHero moves on to its next candidate.

Rejected YouTube ids are remembered in
$XDG_STATE_HOME/omarchy-backstagehero/rejected-videos, so community resolver
hits and later searches skip them.

Run by hand it checks videos already in a library:
  video_filter.py scan FOLDER...                 list still-image videos
  video_filter.py scan --quarantine FOLDER...    move them out of the song
      folders (into FOLDER/.omarchy-static-videos/, same path below it), so
      the next BackstageHero run downloads a new one. Nothing is deleted.

OMARCHY_BACKSTAGEHERO_FILTER=0 turns all of this off; =titles keeps only the
search part (no frame check).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

# --- titles ---------------------------------------------------------------

# Never a picture worth showing: audio uploads, art tracks, re-edits of the
# audio, and rhythm-game footage (a highway behind the highway).
REJECT_TITLE = [
    r'official\s+audio', r'[(\[]\s*audio\s*[)\]]', r'\baudio\s+only\b',
    r'\bofficial\s+(?:hd\s+|hq\s+)?audio\b', r'\baudio\s*[-:|]\s*official\b',
    r'\bfull\s+album\b', r'\balbum\s+stream\b', r'\bfull\s+ep\b', r'[(\[]\s*album\s*[)\]]',
    r'\bcomplete\s+album\b', r'\bwhole\s+album\b',
    r'\bstatic\s+(?:video|image)\b', r'\bcover\s+art\b', r'\balbum\s+art\b',
    r'\b8d\s+audio\b', r'\bnightcore\b', r'\bslowed\b', r'\bsped\s+up\b',
    r'\breverb\b', r'\bbass\s*boost', r'\bkaraoke\b',
    r'\bguitar\s+hero\b', r'\brock\s+band\b', r'\bclone\s+hero\b', r'\byarg\b',
    r'\bexpert\s*\+', r'\b100\s*%\s*fc\b', r'\bfull\s+combo\b', r'\bchart\s+preview\b',
]
# A still or near-still picture more often than not: tried after the rest.
PENALTY_TITLE = [
    (r'\blyrics?\b|\blyric\s+video\b|\bletra\b|\blegendado\b|\bparoles\b', 3),
    (r'\bremaster(?:ed)?\b', 2),
    (r'[(\[]\s*h[qd]\s*[)\]]|\bhq\b|\bhigh\s+quality\b', 2),
    (r'\bvisuali[sz]er\b', 1),
    (r'\bcover\b|\btutorial\b|\blesson\b|\breaction\b|\breacts?\b', 3),
    (r'\binstrumental\b|\bbacking\s+track\b|\bisolated\b|\bstems?\b', 3),
]
PREFER_TITLE = [
    (r'\bofficial\s+(?:hd\s+|4k\s+)?(?:music\s+)?video\b', 4),
    (r'\bmusic\s+video\b|\bvideo\s*clipe?\b|\bclipe?\s+oficial\b|\bvideoclip\b', 3),
    (r'[(\[]\s*(?:official\s+)?(?:mv|m/v|pv)\s*[)\]]|\bofficial\s+mv\b', 3),
    (r'\blive\b|\bperformance\b|\bconcert\b|\bsession\b|\bunplugged\b', 2),
    (r'\banimated\b|\banimation\b', 2),
]
# Auto-generated art tracks carry this in the description; YouTube's own
# "Topic" channels only ever post them.
REJECT_DESCRIPTION = [r'^\s*provided\s+to\s+youtube\s+by\b', r'auto-generated\s+by\s+youtube']
REJECT_CHANNEL = [r'\s-\s*topic\s*$', r'^release\s*-\s*topic$']
PREFER_CHANNEL = [(r'vevo\s*$', 2)]


def _any(patterns, text):
    return any(re.search(p, text, re.I) for p in patterns)


def _strip_song(text, song):
    """The video title minus the song's own name: a song called "Audio" or
    "Live Forever" says nothing about the upload."""
    if not song:
        return text
    for part in re.split(r'\s+-\s+|\s+', song.strip()):
        if len(part) > 2:
            text = re.sub(r'\b' + re.escape(part) + r'\b', ' ', text, flags=re.I)
    return text


def judge(title, channel='', description='', song=''):
    """(score, reason) for one search result. reason is set when it should be
    dropped; otherwise higher scores are tried first."""
    t = _strip_song(title or '', song)
    channel = channel or ''
    if _any(REJECT_CHANNEL, channel):
        return 0, 'auto-generated art track (Topic channel)'
    if _any(REJECT_DESCRIPTION, description or ''):
        return 0, 'auto-generated art track ("Provided to YouTube by")'
    for p in REJECT_TITLE:
        if re.search(p, t, re.I):
            return 0, 'title: ' + re.search(p, t, re.I).group(0).strip()
    score = 0
    for p, w in PREFER_TITLE:
        if re.search(p, t, re.I):
            score += w
    for p, w in PREFER_CHANNEL:
        if re.search(p, channel, re.I):
            score += w
    for p, w in PENALTY_TITLE:
        if re.search(p, t, re.I):
            score -= w
    return score, None


# No song video runs this long: a whole album or a compilation (a song named
# like its album draws mostly these).
MAX_DURATION = 20 * 60


def rank(entries, song='', rejected_ids=()):
    """Search entries (dicts with id/title/channel/description) -> (kept, dropped),
    kept best first (ties keep YouTube's order), dropped as (entry, reason)."""
    kept, dropped = [], []
    for i, e in enumerate(entries):
        if e.get('id') in rejected_ids:
            dropped.append((e, 'rejected before (still image)'))
            continue
        if (e.get('duration') or 0) > MAX_DURATION:
            dropped.append((e, f'{int(e["duration"]) // 60} min long: an album or compilation'))
            continue
        score, why = judge(e.get('title') or '', e.get('channel') or e.get('uploader') or '',
                           e.get('description') or '', song)
        if why:
            dropped.append((e, why))
        else:
            kept.append((-score, i, e))
    return [e for _, _, e in sorted(kept, key=lambda k: k[:2])], dropped


# --- frames ---------------------------------------------------------------

FRAME_W, FRAME_H = 64, 36
PIXEL_DELTA = 16          # grey levels for a pixel to count as changed
CHANGED_SHARE = 0.10      # share of changed pixels for two frames to differ (lyric
                          # lines over a cover stay below it, cuts and camera moves don't)
MOVING_SHARE = 0.35       # share of differing frame pairs for a real video
MIN_FRAMES = 12


def _frames(path, keyframes_only, duration=None):
    """Grey 64x36 frames sampled from a video, as bytes objects."""
    cmd = ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error']
    if keyframes_only:
        cmd += ['-skip_frame', 'nokey', '-i', path, '-vsync', 'vfr', '-vf']
        vf = ''
    else:
        cmd += ['-i', path, '-vf']
        rate = 40 / duration if duration and duration > 0 else 0.5
        vf = f'fps={rate:.4f},'
    cmd += [vf + f'scale={FRAME_W}:{FRAME_H}:flags=area,format=gray',
            '-an', '-f', 'rawvideo', '-']
    out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                         timeout=600).stdout
    size = FRAME_W * FRAME_H
    return [out[i:i + size] for i in range(0, len(out) - size + 1, size)]


def _duration(path):
    try:
        out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                              '-of', 'csv=p=0', path], capture_output=True, text=True,
                             timeout=60).stdout
        return float(out.strip())
    except (ValueError, OSError, subprocess.SubprocessError):
        return None


def motion(frames):
    """Share of consecutive frame pairs whose picture changed (0..1), or None
    with fewer than two frames."""
    if len(frames) < 2:
        return None
    need = CHANGED_SHARE * len(frames[0])
    moving = 0
    for a, b in zip(frames, frames[1:]):
        changed = sum(1 for x, y in zip(a, b) if abs(x - y) > PIXEL_DELTA)
        moving += changed > need
    return moving / (len(frames) - 1)


def check_video(path):
    """(is_static, motion_share) for a video file. Keyframes are enough for most
    uploads and fast; with too few of them (still images compress to very long
    keyframe gaps) it decodes ~40 evenly spread frames instead. motion_share is
    None if ffmpeg read no picture, which does not count as static."""
    frames = _frames(path, True)
    if len(frames) < MIN_FRAMES:
        frames = _frames(path, False, _duration(path))
    share = motion(frames)
    return (share is not None and share < MOVING_SHARE), share


# --- remembered rejections --------------------------------------------------

def _state_file():
    base = os.environ.get('XDG_STATE_HOME') or os.path.expanduser('~/.local/state')
    return os.path.join(base, 'omarchy-backstagehero', 'rejected-videos')


def rejected_ids():
    try:
        with open(_state_file(), encoding='utf-8') as f:
            return {line.split()[0] for line in f if line.strip()}
    except OSError:
        return set()


def remember_rejected(video_id, why):
    if not video_id:
        return
    path = _state_file()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'a', encoding='utf-8') as f:
        f.write(f'{video_id} {why}\n')


# --- hooks into BackstageHero -------------------------------------------------

class StaticVideo(Exception):
    """The downloaded video is a still picture."""


def install(vd, resolver=None, mode=None):
    """Patch BackstageHero's VideoDownload module (and resolver_client)."""
    mode = mode or os.environ.get('OMARCHY_BACKSTAGEHERO_FILTER', '1')
    if mode == '0':
        return
    orig_download = vd.download_video
    search_n = max(getattr(vd, 'SEARCH_RESULTS', 5), 5) * 2

    def _search(query, n):
        opts = vd._base_opts()
        opts['extract_flat'] = True
        try:
            with vd.yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(f'ytsearch{n}:{query}', download=False)
        except Exception as e:
            if vd.is_bot_error(e):
                raise vd.BotDetected(str(e))
            raise
        return [e for e in (info or {}).get('entries') or [] if e and e.get('id')]

    def search_candidates(query, n=vd.SEARCH_RESULTS):
        """Same contract as BackstageHero's: (url, title, duration) tuples, best
        first, raising when nothing is usable."""
        bad = rejected_ids()
        entries = _search(query, max(n, search_n))
        kept, dropped = rank(entries, song=query, rejected_ids=bad)
        if not kept:
            more = _search(query + ' official video', search_n)
            seen = {e['id'] for e in entries}
            kept, dropped2 = rank([e for e in more if e['id'] not in seen], song=query,
                                  rejected_ids=bad)
            dropped += dropped2
        for e, why in dropped:
            print(f'  Skipping "{e.get("title")}" ({why})')
        if not kept:
            raise Exception('No real video (only audio uploads / still images) for: ' + query)
        return [(f"https://www.youtube.com/watch?v={e['id']}", e.get('title', 'Unknown'),
                 e.get('duration')) for e in kept[:n]]

    def download_video(folder, url, quality, info=None):
        final = os.path.join(folder, 'video.mp4')
        backup = os.path.join(folder, 'video.omarchy-prev.mp4')
        had_old = os.path.isfile(final)
        if had_old:
            if os.path.lexists(backup):
                os.remove(backup)
            try:
                os.link(final, backup)
            except OSError:
                shutil.copy2(final, backup)
        try:
            orig_download(folder, url, quality, info=info)
            if mode == 'titles' or not os.path.isfile(final):
                return
            static, share = check_video(final)
            if not static:
                return
            vid = vd.video_id_of(url)
            print(f'  Video is a still picture (moving in {share:.0%} of samples), trying another')
            remember_rejected(vid, f'still picture, motion {share:.2f}')
            if had_old:
                os.replace(backup, final)
            else:
                os.remove(final)
            raise StaticVideo('still picture: ' + url)
        finally:
            if os.path.lexists(backup):
                os.remove(backup)

    vd.search_candidates = search_candidates
    vd.download_video = download_video
    vd.StaticVideo = StaticVideo

    if resolver is not None and hasattr(resolver, 'resolve'):
        orig_resolve = resolver.resolve

        def resolve(*a, **kw):
            hit = orig_resolve(*a, **kw)
            if hit and hit.get('video_id') in rejected_ids():
                print('  Community video skipped (rejected before as a still picture)')
                return None
            return hit
        resolver.resolve = resolve


# --- library scan -----------------------------------------------------------

VIDEO_NAMES = ('bg.webm', 'bg.mp4', 'video.mp4', 'video.webm')
QUARANTINE = '.omarchy-static-videos'


def scan(roots, quarantine=False, out=sys.stdout):
    """Check song videos below roots; returns the static ones as (folder, files)."""
    found = []
    for root in roots:
        root = os.path.realpath(root)
        if not root or root == '/' or not os.path.isdir(root):
            print(f'skipping {root!r}: not a song folder', file=sys.stderr)
            continue
        for dp, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d != QUARANTINE]
            names = {f.lower(): f for f in files}
            if 'song.ini' not in names:
                continue
            vids = [names[n] for n in VIDEO_NAMES if n in names]
            if not vids:
                continue
            static, share = check_video(os.path.join(dp, vids[0]))
            if not static:
                continue
            found.append((dp, vids))
            print(f'STATIC {share:.2f}  {dp}', file=out)
            if quarantine:
                _quarantine(root, dp, vids, out)
    print(f'{len(found)} still-picture videos', file=out)
    return found


def _quarantine(root, folder, vids, out):
    rel = os.path.relpath(folder, root)
    if rel.startswith('..') or rel == '.':
        rel = os.path.basename(folder)
    dest = os.path.join(root, QUARANTINE, rel)
    os.makedirs(dest, exist_ok=True)
    for v in vids:
        src = os.path.join(folder, v)
        target = os.path.join(dest, v)
        if os.path.isfile(src) and not os.path.exists(target):
            os.replace(src, target)
            print(f'  moved {v} -> {target}', file=out)
    # The community resolver would hand BackstageHero the same video again.
    source = _ini_value(os.path.join(folder, 'song.ini'), 'backstagehero_source')
    if source and source not in rejected_ids():
        remember_rejected(source, 'still picture (library scan)')


def _ini_value(path, key):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                k, sep, v = line.partition('=')
                if sep and k.strip().lower() == key:
                    return v.strip()
    except OSError:
        pass
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('scan', help='find still-picture song videos')
    s.add_argument('folders', nargs='+')
    s.add_argument('--quarantine', action='store_true',
                   help='move them out of the song folders (nothing is deleted)')
    c = sub.add_parser('check', help='motion share of single video files')
    c.add_argument('files', nargs='+')
    j = sub.add_parser('judge', help='score a video title')
    j.add_argument('title')
    j.add_argument('--channel', default='')
    j.add_argument('--description', default='')
    a = ap.parse_args(argv)
    if a.cmd == 'scan':
        scan(a.folders, a.quarantine)
    elif a.cmd == 'check':
        for f in a.files:
            static, share = check_video(f)
            print(f'{"STATIC" if static else "OK    "} {share if share is None else round(share, 2)}  {f}')
    else:
        print(judge(a.title, a.channel, a.description))


if __name__ == '__main__':
    main()
