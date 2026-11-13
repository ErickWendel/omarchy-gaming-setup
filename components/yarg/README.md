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

Overrides: `OMARCHY_YARG_DIR`, `OMARCHY_YARG_SONGS`,
`OMARCHY_YARG_SHARED_SETTINGS`, `YARG_BIN`.

## Adding songs

Unpack them anywhere inside `/wdblack_4TB/Games/YARC/Songs` and use
**Refresh Song Library** in YARG's settings.
