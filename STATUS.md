# Current implementation and verification status

Last updated: 2026-10-12 (G29 PS4-mode support installed, handbrake fix added; earlier rows from 2026-10-11 after reboot).

This is the resume point for the next work session. Do not rerun the initial
investigation or close the unresolved GitHub issues solely because their files
and services are installed.

## User-verified results

| Component | Result | Current status |
| --- | --- | --- |
| OpenRGB (#3) | Pass | `static-green` was applied automatically after reboot/login. |
| Delta Center (#4) | Fail | The desktop window still opens automatically after login. |
| Steam Big Picture (#5) | Fixed, awaiting user check | Root cause found and fixed in helper `51077c4`; automated live cycles pass. A real PS-button run still needs user verification. |
| G29 wheel in PS4 mode (#9) | Implemented, awaiting user check | Mode switch to native `c24f` verified live with force feedback; udev rule installed and `check` passes; replug, reboot, and Forza still need user verification. |
| USB handbrake | Fixed after reboot, awaiting in-game check | Kernel quirk active; bound to `hid-generic`. evtest: pull drives `ABS_RUDDER` 0→~240 and returns to 0. FH5 did not see it through SDL (mapped as a RumblePad 2 gamepad); hidraw rule + `PROTON_ENABLE_HIDRAW` launch option pending. |
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
`hid-generic` binds it. Not installed yet: run
Installed and verified after the 17:24 reboot: `check` passes and the
handbrake is `/dev/input/event*`; pulling it drives `ABS_RUDDER` 0→~240 (evtest).

## Repository publication

The Steam helper fix is published as `ErickWendel/ps5-steam-big-picture@51077c4`
and pinned through `STEAM_HELPER_REF` in `config/machine.example.env`;
`scripts/apply-fast-fixes.sh` installs exactly that commit. The Delta
repository still has local commits that were not pushed.
