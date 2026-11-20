# BackstageHero

[BackstageHero](https://github.com/AARP41298/BackstageHero) finds a music
video for each song that has none, lines it up with the chart audio and saves
it in the song folder as `video.mp4`/`.webm`, which YARG (and Clone Hero)
play behind the highway. This is AARP41298's fork of
[jmb988/BackstageHero](https://github.com/jmb988/BackstageHero): branch
`main-con-suppot`, which adds a music video database (direct links instead of
YouTube searches) and Rock Band CON pack support.

```bash
./components/backstagehero/install.sh         # install or update
./components/backstagehero/install.sh check
omarchy-backstagehero                          # or "BackstageHero" in the app menu
```

## How it is installed

The fork only releases a Windows `.exe`, so this runs the Python source:

- Source in `~/.local/share/omarchy-backstagehero/src`, pinned to a reviewed
  commit (`commit=` in `install.sh`). Raise the pin by hand after reading
  the new commits.
- A uv virtualenv (`venv/`, Python 3.12, which bundles Tk; the system Python
  has no Tk) with `requirements.txt`. ffmpeg and libmpv come from the system.
- `omarchy-backstagehero` sets `LOCALAPPDATA=~/.local/share`, so its
  settings, caches and logs go to `~/.local/share/BackstageHero` instead of
  `~/BackstageHero`, and starts in `/wdblack_4TB/Games`, where its folder
  picker opens (`OMARCHY_BACKSTAGEHERO_START` changes that).

Review notes (commit `cc48438`): it talks to YouTube/Vimeo (via yt-dlp),
GitHub and PyPI (update checks), and `backstage.jimmyproton.co.uk`, a shared
offset database. Song lookups send a hash of the chart files there; sharing
your own offsets back is on by default and can be turned off in the app (or
`BACKSTAGEHERO_NO_SHARE=1`). Its self-updater and yt-dlp updater only run in
the frozen `.exe`, so they do nothing here; `install.sh` updates yt-dlp.

## Real videos, not cover art

Left alone, BackstageHero takes the first search result whose audio matches
the chart, and the best audio matches are often uploads with nothing to watch:
"Official Audio", "Provided to YouTube by ..." art tracks from "- Topic"
channels, cover-plus-lyrics slideshows. Of its first 41 downloads here, 34
were a still picture. `video_filter.py`, hooked in by `omarchy-bh-run.py`
(upstream source stays untouched), changes two steps:

- **Search**: pulls 10 results instead of 5 and drops audio-only uploads by
  title (official audio, `[Audio]`, full album, nightcore/slowed/8D,
  karaoke, Guitar Hero / Rock Band / Clone Hero footage), channel (`- Topic`)
  and description ("Provided to YouTube by"). The rest are ordered official
  video > music video / MV > live / performance > plain > lyrics, remaster,
  "HQ", cover. Words from the song's own name don't count. If nothing is left
  it searches once more with "official video" added.
- **Download**: samples the video's keyframes (or ~40 frames when keyframes
  are sparse) at 64x36 grey with ffmpeg. A frame pair "moves" when over 10% of
  its pixels change; under 35% moving pairs is a still picture (a cover, a
  slideshow, lyric lines over a cover). Real music videos measure ~100%. The
  still video is dropped, any earlier video put back, and BackstageHero tries
  its next candidate. Its id goes to
  `~/.local/state/omarchy-backstagehero/rejected-videos`, so searches and
  community resolver hits skip it later.

`OMARCHY_BACKSTAGEHERO_FILTER=0` turns it off, `=titles` keeps only the
search part. Songs with no real video end up with none, so YARG shows its
venue.

Videos already downloaded can be checked; `--quarantine` moves the still
ones (all of `bg.webm`/`video.mp4`/...) to `FOLDER/.omarchy-static-videos/`
under the same path, so the next BackstageHero run fetches a new one, and
remembers their ids as rejected. Nothing is deleted; move a file back to undo.

```bash
omarchy-backstagehero scan /wdblack_4TB/Games/YARC/Songs-UltimateREpack
omarchy-backstagehero scan --quarantine /wdblack_4TB/Games/YARC/Songs-UltimateREpack
```

## Using it

It works on one Songs folder at a time (not remembered between runs). Pick a
folder such as `/wdblack_4TB/Games/YARC/Songs-UltimateREpack` or a single
`CloneHero-Drive/Songs/<pack>`; the whole 1.5 TB Drive mirror is far more
than YouTube lets one machine download without throttling. Songs that
already have a video are skipped, so reruns only fill in what is missing.

Rock Band CON packs need the fork's Nautilus build, which is a Windows .NET
app and is not set up here; song folders with `song.ini` work without it.

In YARG a song's own video replaces the venue unless "Disable per-song
backgrounds" is on.

Videos it saves are H.264 `video.mp4` with Clone Hero's offset sign, neither
of which YARG on Linux handles; the launcher fixes both around each run (see
"Song videos on Linux" in `components/yarg/README.md`). Start it from the app
menu or `omarchy-backstagehero` for that to happen.
