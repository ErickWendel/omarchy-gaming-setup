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
