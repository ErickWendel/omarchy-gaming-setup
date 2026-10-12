# Current implementation and verification status

Last updated: 2026-10-12, after live Steam/PCSX2 controller testing.

This is the resume point for the next work session. Do not rerun the initial
investigation or close the unresolved GitHub issues solely because their files
and services are installed.

## User-verified results

| Component | Result | Current status |
| --- | --- | --- |
| OpenRGB (#3) | Pass | `static-green` was applied automatically after reboot/login. |
| Delta Center (#4) | Fail | The desktop window still opens automatically after login. |
| Steam Big Picture (#5) | Scope changed | Returning to Big Picture after a game is abandoned (see below). PS opens Big Picture from the desktop and Steam's own menu in Steam games; awaiting a final user run with helper `cf103d6`. |
| PCSX2 controllers (#7) | Partial pass | Controllers work with Steam Input disabled; Share + Options opens PCSX2's pause menu (user-verified). PS → PCSX2 pause menu via `Escape` is installed and awaiting a user run. |

## Installed state

- OpenRGB's internal `AutoStart.enabled` is `false`, its legacy active XDG
  autostart entry is absent, and `openrgb.service` is enabled for the graphical
  session. The reboot test passed.
- Delta's legacy `~/.config/autostart/delta-center.desktop` was disabled.
  `delta-center.service` is installed and enabled with
  `delta-center-launch --hidden`, but the application still showed its window.
  This proves that the unit argument alone does not produce the required
  behavior on the installed runtime, or that another startup path remains.
- Helper `cf103d6` is installed: PS opens Big Picture only when no game runs,
  is left to Steam Input during Steam games, and sends `Escape` to PCSX2. It
  no longer polls processes/windows or touches Steam's windows.
- All nine detected PCSX2 Steam shortcuts call `~/.local/bin/omarchy-pcsx2`
  and have Steam Input disabled. The launcher forces `QT_QPA_PLATFORM=xcb`.
- `PCSX2.ini` uses the Vulkan renderer and the managed hotkeys from
  `components/pcsx2/configure_pcsx2_ini.py`.
- Steam starts once at login, from its own `~/.config/autostart/steam.desktop`;
  the duplicate `steam -silent` Hyprland launch was removed
  (`components/steam/install.sh`).
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

## Steam and PCSX2 on Hyprland — findings (2026-10-12)

- **Big Picture return is not fixable from outside Steam.** Steam's UI mode
  (`SSGL: UI mode (4->7)` in `gameprocess_log.txt`) is internal. Every helper
  attempt to restore it — re-sending the URI, refocusing/fullscreening the
  window, a return state machine — raced Steam and caused worse failures:
  games opening behind a fullscreen (black) Big Picture window and controller
  input routed to a hidden window. All of that was removed; Big Picture may
  drop to desktop after a game and PS reopens it.
- **The helper must not act on PS during Steam games.** It reads the same
  evdev events as Steam Input; acting on them as well (URI, `Shift+Tab`)
  conflicted with Steam's own Guide handling.
- **Steam only sees X11 windows.** PCSX2 defaulted to native Wayland, so Steam
  kept routing controller input to Big Picture behind the game. The launcher
  now forces XWayland (`QT_QPA_PLATFORM=xcb`).
- **Steam's overlay cannot drive PCSX2.** With Vulkan the overlay draws, but
  it drew misplaced and never received controller input: Steam's hooks rely
  on Xlib while Qt uses xcb. A Hyprland `focus_on_activate = false` rule for
  Steam and `GDK_SCALE=1` were tried and did not help, so neither was kept.
  PCSX2 therefore keeps Steam Input disabled and uses its own pause menu.
- **SDL slot order varies.** A connected G29 wheel becomes `SDL-0`, making the
  PS5 pad `SDL-1`. The pause-menu hotkey is bound on `SDL-0`..`SDL-3`; the
  other PCSX2 hotkeys and player 1 still follow `SDL-0`.
- **Forza's black screen was a resolution mismatch.** Forza Horizon 5 was set
  to exclusive fullscreen at 2560x1440 on the 3440x1440 monitor. Proton fakes
  the mode change with an extra, empty fullscreen window that covered the game
  (the real window floated underneath). Setting `ResolutionWidth` to 3440 in
  the game's `UserConfigSelections` (or Options > Video > Resolution in game)
  fixed it: the game now holds a stable 3440x1440 fullscreen window. Hyprland
  rules for the two windows were tried and are not needed. Other Proton games
  showing a black screen should be checked for the same non-native fullscreen
  resolution first.
- **Resolution follows the display.** `components/steam/match-resolution`
  (installed as `~/.local/bin/omarchy-match-resolution`) is set as Forza's
  Steam launch option. Before each launch it writes the focused Hyprland
  monitor's resolution (3440x1440 ultrawide or 3840x2160 TV) into the game's
  settings; games are mapped by `SteamAppId` in its `GAMES` table. Verified:
  a deliberately wrong 2560 width was corrected to 3440 at launch. That test
  launch exited after 24 s for an unconfirmed reason; recheck Forza.

## Remaining user verification

- In a Steam-launched PS2 game, press PS and confirm PCSX2's pause menu opens
  and is navigable; Share + Options must do the same.
- In a Steam game (Forza), press PS and confirm Steam's menu opens over the
  game and the controller works after closing it.
- On the desktop with no game, press PS and confirm Big Picture opens.

## Repository publication

The Steam helper is pinned to `ErickWendel/ps5-steam-big-picture@cf103d6`
through `STEAM_HELPER_REF` in `config/machine.example.env`;
`scripts/apply-fast-fixes.sh` installs exactly that commit. The Delta
repository still has local commits that were not pushed.
