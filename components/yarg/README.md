# YARG

[YARG](https://yarg.in) is installed with the YARC launcher, which puts it in
`/wdblack_4TB/Games/YARC/YARG Installs/<profile>/installation/YARG`. Songs
live in `/wdblack_4TB/Games/YARC/Songs` (Clone Hero / Rock Band folders with
`song.ini`, `.mid` and `.ogg`; YARG scans subfolders).

```bash
./components/yarg/install.sh          # Steam must be closed
./components/yarg/install.sh check
```

Install puts `~/.local/bin/omarchy-yarg` in place, fetches the Windows
build of the same release (`install-windows.sh`, see "The Windows build"),
adds a "YARG" entry to the app menu (`~/.local/share/applications/yarg.desktop`,
icon copied from the Steam shortcut's artwork), and adds a native "YARG"
non-Steam shortcut that runs `omarchy-yarg`. The Steam guest shares your
Steam, so the shortcut shows up in its Big Picture as well.

Since 2026-11-21 `omarchy-yarg` runs the **Linux build** by default: it is
the only one that sees the PS3 Guitar Hero drums and guitars (see "PS3 / Wii
instruments"). Song videos need the VP8 `bg.webm` copies
(`omarchy-yarg-videos`) and the CRKD guitar is bound by hand.
`OMARCHY_YARG_PLATFORM=windows` runs the Windows build under GE-Proton
(H.264 videos as they are, CRKD recognised; used 2026-11-20 to 2026-11-21).

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

## PS3 / Wii instruments (Guitar Hero drums and guitars)

PS3 Guitar Hero and Rock Band dongles (RedOctane/Sony `12ba:*`, such as the
GH drum kit `12ba:0120` and GH5 guitars `12ba:0100`) and Wii Rock Band ones
(`1bad:*`) are recognised by YARG from their raw HID reports. Proton's
winebus (and the Linux build) read them from `/dev/hidraw*`, which is
root-only by default; without access they show up as plain joysticks or not
at all. `install-instruments.sh` installs `71-omarchy-yarg-instruments.rules`
(tags those nodes `uaccess`, needs sudo); `install-instruments.sh check`
lists connected instruments and whether they are readable.

The Windows build does not see them as instruments: on Windows YARG
(HIDrogen) reads HID instruments through GameInput, which fails under Wine
("Failed to create GameInput instance: 0x80070485"). Proton's SDL layer
offers each dongle as an "Xbox Controller" instead, without the
guitar/drum layout. Blocking that copy (`SDL_JOYSTICK_BLACKLIST_DEVICES`)
leaves only the raw HID one, which YARG then doesn't list at all (checked
2026-11-21). The Linux build (the default) reads them: HIDrogen opens
`/dev/hidraw*` directly, and it created the drums profile by itself. Plug the dongle in
before starting YARG, then add the instrument under Profiles / Players.

Bind the PS3 guitar through YARG's `PS3GuitarHeroGuitar` entry, not the
generic `Linux::...GuitarHero5forPlayStationR3` joystick (no fret layout).
Identical dongles have no serial and YARG stores the same device hash for
each, so with two guitar dongles plugged in and one guitar paired it may read
the empty one (frets show nothing on the Binds screen). Unplug the unpaired
dongle (blinking light). Checked 2026-11-21: GH5 guitar and drum kit both
work this way.

Overrides: `OMARCHY_YARG_DIR`, `OMARCHY_YARG_SONGS`,
`OMARCHY_YARG_SHARED_SETTINGS`, `OMARCHY_YARG_PLATFORM`, `OMARCHY_YARG_BACKEND`, `OMARCHY_YARG_MONITOR`,
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

**VP8 copies (Linux build only).** `omarchy-yarg-videos` (`webm-videos.py`) fixes both halves:

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
starts and `omarchy-yarg-videos --no-video` (a `systemd-run` unit) after it
closes. With the Linux build (the default) it also writes the VP8 copies;
with `OMARCHY_YARG_PLATFORM=windows` it fixes offsets only
(`OMARCHY_YARG_CONVERT_VIDEOS=0/1` overrides). Song folders come from the Linux and Windows
`settings.json` files (Wine `Z:\` paths are translated). After new videos,
rescan songs in YARG. `omarchy-yarg-videos --remove-copies [--dry-run]`
deletes the `bg.webm` copies it made (tagged `omarchy-webm*`, next to their
source video) and nothing else; the 27 copies (3.2 GB) were removed on
2026-11-20.

## The Windows build (`OMARCHY_YARG_PLATFORM=windows`)

Reported upstream in
[YARC-Official/YARG#1776](https://github.com/YARC-Official/YARG/issues/1776).

- **Install:** `install-windows.sh [TAG]` downloads YARC's Windows zip for
  the newest Nightly the YARC launcher installed (or TAG: `bNNNN`, `vX.Y.Z`)
  into `/wdblack_4TB/Games/YARC/omarchy-windows/<tag>/`. After the YARC
  launcher updates YARG, run it again (`install.sh check` says when it's
  missing). `omarchy-yarg` picks the newest Windows install of the channel.
- **Run:** GE-Proton11-1 (`OMARCHY_YARG_PROTON`) in a prefix per account at
  `~/.local/share/omarchy-yarg/proton` (`OMARCHY_YARG_PREFIX`). Settings live
  in the prefix, `.../AppData/LocalLow/YARC/YARG/<nightly|release>`, and are
  shared with the guest as before. On your first start they are copied from
  the Linux settings of the same channel, song folders turned into `Z:\`
  paths; items already there (the Windows bindings) are kept.
- **Videos:** the zip ships `VLCUnityPlugin.dll` but no libVLC, so YARG falls
  back to Unity's VideoPlayer, which on Windows decodes through Media
  Foundation; Proton 11 backs that with FFmpeg, so H.264 `video.mp4` plays,
  in sync. "Color primaries 0 is unknown" in the log is harmless.
- **Window:** under XWayland it has the same menu-click problem as the Linux
  build, so it runs on Wine's Wayland driver (`PROTON_ENABLE_WAYLAND=1`;
  `OMARCHY_YARG_WAYLAND=0` turns it off). Unity keeps the monitor and size
  it last used and doesn't resize when moved (a size saved on the HDMI screen
  left a 1920x1080 window on the ultrawide), so the launcher passes
  `-monitor N -screen-width W -screen-height H -screen-fullscreen 1` for the
  largest monitor (or `OMARCHY_YARG_MONITOR`). Wine numbers monitors left to
  right, not by Hyprland id. `-monitor`/`-screen-width` on the command line
  win.
- **Guitar:** the CRKD (over Bluetooth, "Guitar-Dongle", 1949:0402) reaches
  Wine as an XInput device; the Windows build recognises it as a CRKD guitar
  and binds it by itself.
- **Song names:** Windows programs can't open names with `< > : " | ? *` or
  ending in a dot or space; YARG logs "Invalid name" / "Could not find a part
  of the path" and skips the song. `omarchy-yarg-windows-names`
  (`windows-names.py`; dry run, `--apply`, `--restore`) swaps those
  characters for full-width lookalikes (`：` `？` `＊` ...) and drops trailing
  dots and spaces, deepest first, skipping any rename onto an existing name,
  and logs each rename in `~/.local/state/omarchy-yarg/windows-names.tsv`.
  2026-11-20: 280 names renamed (about 100 charts, all under `[CHORUS]`);
  the scan then logs no path errors. Run it again after adding songs.
- **Known log noise:** an unsupported URP shader (DBufferClear), GameInput
  and WinMM MIDI errors.
- **Not yet checked:** audio latency against the Linux build, a run from the
  guest login (it gets its own prefix on first start).

## Duplicate charts

`dedupe-songs.py FOLDER...` (dry run; `--apply` to move) keeps the most
complete chart of each artist/title and moves the rest to
`/wdblack_4TB/Games/CloneHero-Duplicates`, listed in `moved.tsv`
(`--restore` puts them back). 2026-11-20: 34,438 charts (407 GB) moved;
75,519 left. Rescan songs in YARG afterwards.

## Playlists per game

`omarchy-yarg-playlists` (`game-playlists.py`; `--dry-run` to preview) writes
one YARG playlist per Guitar Hero / Rock Band game, from the per-game folders
in `CloneHero-Drive/Songs/[GUITAR HERO]` and `[ROCK BAND]`. DLC packs join
their game's playlist after the game's own songs (Rock Band 3 DLC goes into
Rock Band 3, Guitar Hero World Tour DLC into Guitar Hero World Tour, ...).
"Guitar Hero (All)" and "Rock Band (All)" hold every game of the franchise
together, game by game. Tutorials, demos and prototypes are left out. Songs that the dedupe moved out
of a game folder still count: the playlist points at the chart that was kept
(from `moved.tsv`).

A playlist entry is the SHA-1 of the song's chart file (`notes.mid`, else
`notes.midi`, else `notes.chart`), the same hash YARG uses. The tool writes
to every YARG settings folder it finds (Windows prefix, and Linux
nightly/release). It replaces only its own playlists, marked Author
`omarchy`, so Favorites and playlists you made yourself stay. Close YARG
before running it, because YARG reads playlists when it starts. Run it again
after adding songs or dedupe changes. 2026-11-21: 28 playlists, 7,134 songs.

Two more playlists cover the whole library (all four YARG song folders):

- **Songs with Videos**: songs with a background video YARG plays (`bg`,
  `background` or `video`, optionally `_clean`/`_explicit`, in
  .mp4/.mov/.webm/.mkv, or the song.ini `video` file). 3,435 songs.
- **Músicas Nacionais**: Brazilian songs, found by artist
  (`BRAZILIAN_ARTISTS` in the script) or by a Brazilian genre tag (MPB,
  forró, sertanejo, axé, pagode, Brazilian rock, ...). Plain "samba" and
  "bossa nova" tags don't count, because non-Brazilian charts use them too.
  671 songs. Add missing artists to the list and rerun.
