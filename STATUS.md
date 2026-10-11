# Current implementation and verification status

Last updated: 2026-10-11, after a full reboot and graphical login.

This is the resume point for the next work session. Do not rerun the initial
investigation or close the unresolved GitHub issues solely because their files
and services are installed.

## User-verified results

| Component | Result | Current status |
| --- | --- | --- |
| OpenRGB (#3) | Pass | `static-green` was applied automatically after reboot/login. |
| Delta Center (#4) | Fail | The desktop window still opens automatically after login. |
| Steam Big Picture (#5) | Fixed, awaiting user check | Root cause found and fixed in helper `51077c4`; automated live cycles pass. A real PS-button run still needs user verification. |
| PCSX2 controllers (#7) | Partial pass | PCSX2 recognizes the controller when Steam Input is disabled. The post-install PS-button overlay behavior still needs verification. |

## Installed state

- OpenRGB's internal `AutoStart.enabled` is `false`, its legacy active XDG
  autostart entry is absent, and `openrgb.service` is enabled for the graphical
  session. The reboot test passed.
- Delta's legacy `~/.config/autostart/delta-center.desktop` was disabled.
  `delta-center.service` is installed and enabled with
  `delta-center-launch --hidden`, but the application still showed its window.
  This proves that the unit argument alone does not produce the required
  behavior on the installed runtime, or that another startup path remains.
- The latest `ps5-steam-big-picture-monitor` is installed, including the
  one-shot lifecycle state machine, Gamepad UI window targeting, and PS-button
  to `Shift+Tab` overlay fallback for Steam-Input-disabled games.
- All nine detected PCSX2 Steam shortcuts now call
  `~/.local/bin/omarchy-pcsx2` and have Steam Input disabled. Their prior Steam
  configuration is backed up under
  `~/.local/state/omarchy-gaming-setup/backups/20261011-185102-pcsx2/`.
- Pre-activation copies of the replaced Delta and Steam helper files are under
  `~/.local/state/omarchy-gaming-setup/backups/manual-activation-20261011/`.

## Next investigation: Delta Center

The next session should collect evidence before changing the launcher again:

```bash
systemctl --user status delta-center.service --no-pager
systemctl --user cat delta-center.service
journalctl --user -u delta-center.service -b --no-pager
pgrep -af 'delta|Delta|electron'
rg -i 'delta|cw360' ~/.config/autostart ~/.config/hypr ~/.config/systemd/user \
  ~/.local/share/applications 2>/dev/null
```

Determine whether the visible window belongs to the managed `--hidden`
process, a second autostart path, or Delta/Electron ignoring `--hidden`. Keep
the normal application-menu entry visible for intentional manual launches.

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

- During a Steam-launched PCSX2 game, press PS and verify that Steam's overlay
  opens through the installed `Shift+Tab` fallback.
- Launch PCSX2 directly through `~/.local/bin/omarchy-pcsx2` and verify both
  controllers still work.
- Repeat the Steam return-once and stay-minimized-for-15-seconds checks in
  `TESTING.md`, pressing PS during the game (it must open the overlay, not
  Big Picture) before closing it.

## Repository publication

The umbrella, Delta, and Steam-helper repositories contain local commits that
were not pushed during this session because the execution environment could
not resolve `github.com`. Push them before updating or closing GitHub issues.
