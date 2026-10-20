# Current implementation and verification status

Last updated: 2026-10-12 (Steam/PCSX2/Forza controller and display fixes;
Delta Center startup fix; G29 PS4-mode and handbrake support).

This is the resume point for the next work session. Do not rerun the initial
investigation or close the unresolved GitHub issues solely because their files
and services are installed.

## User-verified results

| Component | Result | Current status |
| --- | --- | --- |
| OpenRGB (#3) | Pass | `static-green` was applied automatically after reboot/login. |
| Delta Center (#4) | Fixed, awaiting user check | Root cause found: the renamed autostart entry still launched a visible instance. A reboot/login check is still needed. |
| Steam Big Picture (#5) | Scope changed | Returning to Big Picture after a game is abandoned (see below). PS opens Big Picture from the desktop and Steam's own menu in Steam games; awaiting a final user run with helper `b2fbc22`. |
| G29 wheel in PS4 mode (#9) | Accepted by user, issue closed | Native `c24f` mode with force feedback; udev switch installed and `check` passes after reboot. A wheel power-cycle and in-game force feedback were not separately reported. |
| USB handbrake | Bridge installed, accepted by user | `omarchy-handbrake-bridge` exposes an "Omarchy USB Handbrake" plain joystick (SDL-verified). Rerun `handbrake.sh install` (or replug) if `check` reports raw nodes still visible. FH5 still has the unused `PROTON_ENABLE_HIDRAW` launch option; remove it with Steam closed. |
| Assetto Corsa | Fixed, races verified by user | CSP now patches the game on a Proton 9.0 prefix (created with GE-Proton9-20). A full race ran without crashing. Ticking ReShade effects in-game still crashes CSP; edit the preset outside the game. `components/assetto-corsa/assetto-corsa.sh check` passes. |
| NFS Underground 2 PC (Pinnacle of View) | Working, verified 2026-10-20 | ReShade runs as a Vulkan layer over Pinnacle's DXVK (Khronos `vulkan-1.dll`, patched DXVK); every effect compiles and DLSS DLAA runs. `components/nfsu2/nfsu2.sh check` passes. Texmod and dgVoodoo2 were dropped (see the component README). |
| Emulator app entries (#6) | Installed, awaiting user check | Ten validated `omarchy-gaming-*.desktop` entries replaced EmuDeck's tab-indented ones (backups under `~/.local/state/omarchy-gaming-setup/backups/.local/share/applications/`). `emulators.sh check` passes. Steam shortcut reconciliation is still open. |
| PCSX2 controllers (#7) | Partial pass | Controllers work with Steam Input disabled; Share + Options opens PCSX2's pause menu (user-verified). PS → PCSX2 pause menu via `Escape` is installed and awaiting a user run. |

## Installed state

- OpenRGB's internal `AutoStart.enabled` is `false`, its legacy active XDG
  autostart entry is absent, and `openrgb.service` is enabled for the graphical
  session. The reboot test passed.
- `scripts/delta.sh` manages Delta Center: `delta-center.service` runs
  `delta-center-launch --hidden` for the graphical session and no file in
  `~/.config/autostart` launches Delta. The application-menu entry is kept and
  shows the window of the running service instance (no second instance).
- Helper `b2fbc22` is installed: PS opens Big Picture only when no game runs,
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
- **Forza window rules are managed.** `components/hypr/gaming.lua` (installed
  as `~/.config/hypr/gaming.lua` and loaded by one `require("hypr.gaming")`
  line in `hyprland.lua`) keeps Forza's empty intro window floating at 1x1
  without focus or fullscreen, and opens the titled game window fullscreen.
  User-verified: intros and menu stay fullscreen. Leaving fullscreen is not
  supported while Forza runs in its own fullscreen mode (accepted).
- **Fullscreen goes back to the previous window.** Hyprland allows one
  fullscreen window per workspace; a window opened over a fullscreen one (a
  race from Content Manager, a game from Steam) takes it and does not hand it
  back. `misc.exit_window_retains_fullscreen` gives it to the next window in
  focus history instead (often the wrong one), so it stays off. The
  `fullscreen-restore` user service (`components/hypr`, installed with
  `gaming.lua`) remembers the order windows went fullscreen per workspace and,
  when a fullscreen window closes, focuses the previous one and makes it
  fullscreen again. A launcher that recreates its window (Content Manager) is
  matched by class and title for 4 s. Leaving fullscreen with Super+F opts a
  window out. User-verified with Content Manager and Steam Big Picture.
- **Content Manager hiding to the tray is not a close.** It sometimes hides
  while still fullscreen, before the race window exists. The service took that
  as a close and made Big Picture fullscreen, so the race opened behind it on
  a black screen. A closed window whose process still runs is now treated as
  hidden: only that window coming back gets fullscreen. Other windows get it
  only after the process exits (up to 10 s).
- **Resolution follows the display.** `components/steam/match-resolution`
  (installed as `~/.local/bin/omarchy-match-resolution`) is set as Forza's
  Steam launch option. Before each launch it writes the focused Hyprland
  monitor's resolution (3440x1440 ultrawide or 3840x2160 TV) into the game's
  settings; games are mapped by `SteamAppId` in its `GAMES` table. Verified:
  a deliberately wrong 2560 width was corrected to 3440 at launch. That test
  launch exited after 24 s for an unconfirmed reason; recheck Forza.

## Remaining user verification

- Open Omarchy's app launcher, search for each emulator (Azahar, DuckStation,
  PCSX2, RPCS3, shadPS4, Vita3K, Ryujinx, Xenia, Model 2 Emulator, Steam ROM
  Manager) and launch it.
- Reboot and log in: Delta Center must restore the LCD without opening its
  window, and `./setup.sh --check` must report one hidden instance.
- In a Steam-launched PS2 game, press PS and confirm PCSX2's pause menu opens
  and is navigable; Share + Options must do the same.
- In a Steam game (Forza), press PS and confirm Steam's menu opens over the
  game and the controller works after closing it.
- On the desktop with no game, press PS and confirm Big Picture opens.
- Launch PCSX2 directly through `~/.local/bin/omarchy-pcsx2` and verify both
  controllers still work.

## G29 wheel — PS4 mode (2026-10-12)

The stuck PS4 switch exposes the wheel as `046d:c260`, a DualShock-4 style
HID device that only `hid-generic` binds (no force feedback). Sending the
Logitech "switch mode with detach" command with report ID `0x30` (the same
path `new-lg4ff` uses for the G923 PlayStation edition) re-enumerates it as
native `c24f`, which the installed `new-lg4ff` 0.5.0 binds with 900° range and
full force feedback. Verified live once by hand; the udev rule and helper in
`components/g29/` automate it. Installed and `check` passes after reboot. The wheel has external power, so a
reboot kept it in native mode and did not exercise the udev switch; a
power-cycle/replug test and the Forza checks in `TESTING.md` are pending.
Details and evidence: `components/g29/README.md`.

## USB handbrake (2026-10-12)

The handbrake reports `046d:c219` (Logitech F710/RumblePad 2). `hid-logitech`
claims it, fails rumble setup (`missing HID_OUTPUT_REPORT 0`), and leaves it
unbound, so it has no input node at all. `components/handbrake/` adds
`usbhid.quirks=0x046d:0xc219:0x400000` through a Limine drop-in so
`hid-generic` binds it (verified after the 17:24 reboot; evtest: `ABS_RUDDER`
0→~240). FH5 still did not see it: SDL maps the ID as a RumblePad 2 gamepad and
drops the lever, and `PROTON_ENABLE_HIDRAW` did not help. The global fix is the
`omarchy-handbrake-bridge` service, which hides the raw device and exposes a
plain "Omarchy USB Handbrake" joystick (see `components/handbrake/README.md`).

## Repository publication

The Steam helper is pinned to `ErickWendel/ps5-steam-big-picture@b2fbc22`
through `STEAM_HELPER_REF` in `config/machine.example.env`;
`components/steam/helper.sh` (run by `./setup.sh`) clones the public helper
when no checkout exists and installs exactly that commit. The Delta
repository's local commits, including the migration-helper fix `9fcafe5`,
were pushed on 2026-10-17; this repository does not call that helper.
