# Current implementation and verification status

Last updated: 2026-10-12, after fixing the Delta Center startup root cause.

This is the resume point for the next work session. Do not rerun the initial
investigation or close the unresolved GitHub issues solely because their files
and services are installed.

## User-verified results

| Component | Result | Current status |
| --- | --- | --- |
| OpenRGB (#3) | Pass | `static-green` was applied automatically after reboot/login. |
| Delta Center (#4) | Fixed, awaiting user check | Root cause found: the renamed autostart entry still launched a visible instance. A reboot/login check is still needed. |
| Steam Big Picture (#5) | Fixed, awaiting user check | Root cause found and fixed in helper `51077c4`; automated live cycles pass. A real PS-button run still needs user verification. |
| PCSX2 controllers (#7) | Partial pass | PCSX2 recognizes the controller when Steam Input is disabled. The post-install PS-button overlay behavior still needs verification. |

## Installed state

- OpenRGB's internal `AutoStart.enabled` is `false`, its legacy active XDG
  autostart entry is absent, and `openrgb.service` is enabled for the graphical
  session. The reboot test passed.
- `scripts/delta.sh` manages Delta Center: `delta-center.service` runs
  `delta-center-launch --hidden` for the graphical session and no file in
  `~/.config/autostart` launches Delta. The application-menu entry is kept and
  shows the window of the running service instance (no second instance).
- The latest `ps5-steam-big-picture-monitor` is installed, including the
  one-shot lifecycle state machine, Gamepad UI window targeting, and PS-button
  to `Shift+Tab` overlay fallback for Steam-Input-disabled games.
- All nine detected PCSX2 Steam shortcuts now call
  `~/.local/bin/omarchy-pcsx2` and have Steam Input disabled. Their prior Steam
  configuration is backed up under
  `~/.local/state/omarchy-gaming-setup/backups/20261011-185102-pcsx2/`.
- Pre-activation copies of the replaced Delta and Steam helper files are under
  `~/.local/state/omarchy-gaming-setup/backups/manual-activation-20261011/`.

## Delta Center — root cause and fix (2026-10-12)

`systemd-xdg-autostart-generator` reads every file in `~/.config/autostart`,
regardless of suffix. Renaming the legacy entry to
`delta-center.desktop.disabled-by-omarchy-gaming-setup` therefore still
produced `app-delta\x2dcenter.desktop.disabled…@autostart.service`, which
started a visible Delta Center at login (no `--hidden`) three seconds before
`delta-center.service`. The hidden service instance then hit Electron's
single-instance lock, handed off to the visible one, and exited with status 0
("main closed"). OpenRGB's renamed entry had the same problem and was
running a second, unmanaged `openrgb` process.

The `--hidden` argument itself works: with only the service running, Delta
connects to the LCD, enters live mode, and maps no window.

`scripts/lib/common.sh` now moves retired autostart entries, including copies
renamed by earlier releases, into the backup directory. `./setup.sh` installs
both OpenRGB and Delta through it; `./setup.sh --check` passes all OpenRGB and
Delta checks on this machine, and a second run created no new backups.

## Steam Big Picture — root cause and fix (2026-10-11 evening)

Live traces of the Steam windows and processes, plus Steam's own
`gameprocess_log.txt` (`SSGL: UI mode (4->7)` = Gamepad UI to desktop), showed:

1. On this Hyprland setup a game never runs `gameoverlayui` or `gamescope`.
   The helper therefore never detected a running game: PS presses during
   PCSX2 sent `steam://open/bigpicture` over the game instead of the
   `Shift+Tab` overlay, and the one-shot return never armed.
2. Sending `steam://open/bigpicture` to a live Gamepad UI while a game runs
   makes Steam switch to desktop mode 5–17 s after the game exits. Reproduced
   deterministically; the same cycle without that request keeps Big Picture.
   Steam-native game exits in older logs never dropped Big Picture, because no
   PS presses were mishandled there.
3. Even without the drop, Steam leaves Big Picture floating and windowed
   (2560x1600) after a game exits.

Helper commit `51077c4` detects games by Steam's
`reaper SteamLaunch AppId=...` process. After a game launched from Big Picture
exits, it refocuses and fullscreens the existing Big Picture window, and
re-sends the URI only if the window is gone. Verified live with the NFS U2
PCSX2 shortcut: Big Picture returned fullscreen 2 s after exit, stayed for 40 s,
and a later manual exit to desktop was not reopened.

## Remaining user verification

- Reboot and log in: Delta Center must restore the LCD without opening its
  window, and `./setup.sh --check` must report one hidden instance.

- During a Steam-launched PCSX2 game, press PS and verify that Steam's overlay
  opens through the installed `Shift+Tab` fallback.
- Launch PCSX2 directly through `~/.local/bin/omarchy-pcsx2` and verify both
  controllers still work.
- Repeat the Steam return-once and stay-minimized-for-15-seconds checks in
  `TESTING.md`, pressing PS during the game (it must open the overlay, not
  Big Picture) before closing it.

## Repository publication

The Steam helper fix is published as `ErickWendel/ps5-steam-big-picture@51077c4`
and pinned through `STEAM_HELPER_REF` in `config/machine.example.env`;
`scripts/apply-fast-fixes.sh` installs exactly that commit. The Delta
repository still has local commits that were not pushed, including the
migration-helper fix `9fcafe5`; this repository no longer calls that helper.
