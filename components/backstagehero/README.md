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

Videos it saves are H.264 `video.mp4` with Clone Hero's offset sign. The
Windows build of YARG that `omarchy-yarg` runs plays the MP4 as is; the
offsets still have the opposite sign, so the launcher flips them around each
run (see "Song videos on Linux" in `components/yarg/README.md`). Nothing is
converted unless YARG runs the Linux build (`OMARCHY_YARG_PLATFORM=linux`) or
`OMARCHY_YARG_CONVERT_VIDEOS=1`. Start it from the app menu or
`omarchy-backstagehero` for that to happen.
