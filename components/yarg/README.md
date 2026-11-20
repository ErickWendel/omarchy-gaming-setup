# YARG

[YARG](https://yarg.in) is installed with the YARC launcher, which puts it in
`/wdblack_4TB/Games/YARC/YARG Installs/<profile>/installation/YARG`. Songs
live in `/wdblack_4TB/Games/YARC/Songs` (Clone Hero / Rock Band folders with
`song.ini`, `.mid` and `.ogg`; YARG scans subfolders).

```bash
./components/yarg/install.sh          # Steam must be closed
./components/yarg/install.sh check
```

Install puts `~/.local/bin/omarchy-yarg` in place and adds a native "YARG"
non-Steam shortcut that runs it. The Steam guest shares your Steam, so the
shortcut shows up in its Big Picture as well.

## Artwork

The shortcut's cover, wide capsule, hero, logo and icon are in
`userdata/<id>/config/grid/3495625513*`, from YARG's official branding kit on
SteamGridDB ([game 5452096](https://www.steamgriddb.com/game/5452096): grids
443965 and 443969, hero 106849, logo 93236, icon 43435). They were added by
hand and are not kept in this repo. Install points the shortcut's `icon` field
at `grid/3495625513_icon.png` when that file exists (Steam closed).

## The launcher

`omarchy-yarg` starts the newest YARG install (or `YARG_BIN`) from its own
folder, so YARG updates through the YARC launcher need no change here.

YARG keeps its settings per user in `~/.config/unity3d/YARC/YARG/release`.
Like `omarchy-pcsx2`:

- Your launches copy `settings.json`, `profiles` (players and controller
  bindings) and `custom` (themes, presets) to
  `/wdblack_4TB/Games/YARC/omarchy-shared-settings` at start and exit.
- Guest launches copy them from there at start. Scores, replays and the song
  cache stay per account.
- Both add the song folder to `SongFolders` when it is missing, so a fresh
  account sees the songs on its first start.

The guest reads the launcher through the shared Steam view
(`~/.local/bin` is in `STEAM_SHARED_RO_PATHS`) and the songs through the
games-disk ACLs that `steam-guest.sh install` sets.

### Window backend and monitor

Under XWayland (Unity's default), YARG treats the HDMI monitor as the primary
display. Fullscreen on the ultrawide, it then maps the mouse against the wrong
monitor, so many menu buttons only respond after the window is moved between
monitors. In a Wayland session the launcher starts YARG with
`-force-wayland -force-glcore`: native Wayland sees the real outputs.
Vulkan on Wayland quits at start with the NVIDIA driver ("Surface already has
a fifo"), which is why OpenGL is used.

On Wayland, YARG opens on the display Unity saved, not the focused one, so the
launcher adds `-monitor N` for the largest monitor (the ultrawide), or for
`OMARCHY_YARG_MONITOR=<output>` (for example `HDMI-A-1`). Use
`OMARCHY_YARG_BACKEND=x11` to go back to XWayland. A `-force-x11`,
`-force-wayland` or `-monitor` argument always wins.

## Guitar (CRKD)

The CRKD guitar in PC mode shows up as an Xbox 360 pad
(`Microsoft Guitar Controller`, 045e:028e). YARG on Linux has no guitar layout
for wired XInput devices, so it is a plain Gamepad there and needs manual
binding. With the Mode Dial on a Festival position (2, 3 or 4), Green and Red
are D-pad Left and Right, so a Green+Red chord sends nothing at all.

Overrides: `OMARCHY_YARG_DIR`, `OMARCHY_YARG_SONGS`,
`OMARCHY_YARG_SHARED_SETTINGS`, `OMARCHY_YARG_BACKEND`, `OMARCHY_YARG_MONITOR`,
`YARG_BIN`.

## Adding songs

Unpack them anywhere inside `/wdblack_4TB/Games/YARC/Songs` and use
**Refresh Song Library** in YARG's settings.

## Opening folders from YARG

Under Steam, Steam's overlay library is preloaded (`LD_PRELOAD`) into YARG and
everything it starts. YARG's "Open ... folder" buttons run `xdg-open`, which
runs `/usr/bin/file`; `file`'s seccomp sandbox kills it (SIGSYS, a "Process
crashed: file" notice) when the overlay calls `getuid` at exit, so nothing
opens. The launcher puts an `xdg-open` wrapper in
`$XDG_RUNTIME_DIR/omarchy-yarg-bin`, first on YARG's `PATH`, that drops the
preload and runs the real `xdg-open`.

## Venues and the official setlist

The YARC launcher downloads venues (`Venues/`) and the official setlist
(`Setlists/`) into `/wdblack_4TB/Games/YARC` and starts YARG with
`-download-location` pointing there. YARG looks for them nowhere else, so
`omarchy-yarg` passes the same option. Without it songs fall back to the
plain background. YARG's "Open venue folder" is a separate folder in the
config dir, for venues you add by hand.

## Nightly (career mode)

Career mode is only in YARG Nightly so far. Nightly is installed next to
Stable through the YARC launcher (builds tagged `bNNNN` in `tag.txt`), and
`omarchy-yarg` starts the newest Nightly install;
`OMARCHY_YARG_CHANNEL=stable` goes back to Stable (`vX.Y.Z`). Nightly keeps
its settings in `~/.config/unity3d/YARC/YARG/nightly` instead of `release`.
On your first Nightly start the launcher copies `settings.json`, `profiles`
and `custom` from Stable there, so songs, bindings and presets carry over.
The guest takes them from the shared settings as before. Scores stay with
Stable.

## Song videos on Linux

YARG plays a song's own video (`video.mp4` etc. in the song folder) through
libVLC 4, which Arch doesn't ship (it has VLC 3: `libvlc.so.5`, YARG's
`libVLCUnityPlugin.so` wants `libvlc.so.12`). It then falls back to Unity's
VideoPlayer, which on Linux decodes **VP8 WebM only**, so H.264 `video.mp4`
files show the venue or black.

**Tried and parked (2026-11-20): a private libVLC 4.** `install-vlc4.sh`
takes Chaotic-AUR's prebuilt `vlc-git` (signature checked against their
keyring and project key) and unpacks its libraries and plugins into
`~/.local/share/omarchy-yarg/vlc4`, nothing system-wide. With
`OMARCHY_YARG_VLC_ENABLE=1`, `omarchy-yarg` links `YARG_Data/Plugins/vlc` to it
(YARG sets `VLC_PLUGIN_PATH` there) and puts its libraries on
`LD_LIBRARY_PATH`. YARG then logs "VLC initialized successfully" and VLC
decodes (nvdec), but the picture stays black on this RTX 5070: Wayland EGL on
the NVIDIA GBM node ("GBM EGL display initialization failed: 0x3001"), on the
Intel node (`OMARCHY_YARG_VLC_DRM_DEVICE=/dev/dri/renderD129`, no error),
X11 GLX ("verified-direct-share=1") and X11 Vulkan ("EGL cannot import linear
DRM_FORMAT_ABGR8888"). Once VLC loads, YARG uses it for every video, so it is
off by default and the launcher removes the link. Retry after YARG or VLC
updates.

**In use: VP8 copies.** `omarchy-yarg-videos` (`webm-videos.py`) fixes both halves:

- For each song whose video YARG can't play it writes `bg.webm` (VP8, up to
  1080p, bitrate 2.5x the H.264 source within 2–8 Mbit/s, tagged
  `omarchy-webm-v2`). YARG picks videos by name before extension (bg,
  background, video × .mp4 .mov .webm .mkv), so `bg.webm` wins; the original
  stays. About 25 s per song at nice 15.
- BackstageHero and YARG read `video_start_time` with opposite signs
  (BackstageHero: −L when the song starts L s into the video; YARG: negative
  delays the video, positive skips into it). For songs with
  `backstagehero_source` it negates the value and keeps BackstageHero's as
  `omarchy_bh_video_start_time`; `--offsets backstagehero` puts them back.
  Other charts' offsets are left alone.

`omarchy-backstagehero` runs `--offsets backstagehero` before BackstageHero
starts and `omarchy-yarg-videos` (a `systemd-run` unit) after it closes;
`OMARCHY_YARG_CONVERT_VIDEOS=0` limits that to offsets. Song folders come from YARG's `settings.json`. After new videos,
rescan songs in YARG so it sees `bg.webm`.

## Duplicate charts

`dedupe-songs.py FOLDER...` (dry run; `--apply` to move) keeps the most
complete chart of each artist/title and moves the rest to
`/wdblack_4TB/Games/CloneHero-Duplicates`, listed in `moved.tsv`
(`--restore` puts them back). 2026-11-20: 34,438 charts (407 GB) moved;
75,519 left. Rescan songs in YARG afterwards.
