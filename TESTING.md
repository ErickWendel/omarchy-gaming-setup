# User verification: fast fixes

The latest real-machine results and the exact resume point are recorded in
[STATUS.md](STATUS.md). As of 2026-10-12, OpenRGB passed after reboot,
returning to Big Picture after a game was dropped from scope, and PCSX2
worked with Steam Input disabled. Delta's window-at-login cause was fixed on
2026-10-12 and needs a reboot check.

Apply the reviewed user-level configuration from a terminal:

```bash
cd ~/Downloads/projects/omarchy-gaming-setup
./setup.sh
```

The script exits Steam before editing its shortcut files. It creates backups,
does not format `GExtended`, and does not run games or emulators as root.

After it succeeds, test every section and report pass/fail plus what you saw.
The related GitHub issues remain open until these checks pass.

## OpenRGB — issue #3

1. Confirm the motherboard/device lighting is using `static-green`.
2. Log out and back in once.
3. Confirm the profile is restored without opening the OpenRGB main window.
4. Run `systemctl --user status openrgb.service --no-pager` and confirm it is
   active with no restart loop.

## Delta Center — issue #4

1. Reboot and log in.
2. Confirm the cooler LCD resumes the saved display.
3. Confirm no Delta Center window opens automatically.
4. Run `./setup.sh --check` and confirm every `Delta:` line is `OK`.
5. Open Delta Center from the application menu and confirm its UI still works
   and the check still reports exactly one instance.

## Steam Big Picture — issue #5

1. With no game running, press the PS button and confirm Big Picture opens.
2. Launch a Steam game (for example Forza) and confirm it opens in front.
3. Press PS in the game and confirm Steam's menu opens over the game and can
   be navigated with the controller.
4. Close the menu and confirm the game responds to the controller again.
5. Quit the game. Steam may drop to desktop mode; that is accepted. Pressing
   PS again must reopen Big Picture.

## Emulator application entries — issue #6

1. Run `./components/emulators/emulators.sh check` and confirm every line is
   `OK`.
2. Open Omarchy's app launcher and search for Azahar, DuckStation, PCSX2,
   RPCS3, shadPS4, Vita3K, Ryujinx, Xenia, Model 2 Emulator and Steam ROM
   Manager. Each must appear once with its icon (DuckStation uses a generic
   games icon).
3. Launch two of them from the launcher and confirm the emulator window opens.

## PCSX2 controllers — issue #7

1. Connect both Sony controllers before starting Steam.
2. Start one PS2 game from its existing Steam shortcut.
3. Confirm both controllers work in PCSX2 using the existing player mappings.
4. While the game is running, press PS and confirm PCSX2's pause menu opens
   and can be navigated with the controller. Share + Options must do the same.
   Steam's overlay is intentionally not used in PCSX2.
5. Close the game and launch PCSX2 directly with
   `~/.local/bin/omarchy-pcsx2`; confirm both controllers still work.
6. If either path fails, run
   `~/.local/bin/omarchy-pcsx2 --omarchy-diagnose` and include its output.

## Logitech G29 in PS4 mode — issue #9

Install once (asks for sudo), with the wheel connected and hands off the rim —
it recalibrates when it switches mode:

```bash
./components/g29/g29.sh install
./components/g29/g29.sh check
```

1. Confirm `check` prints `native mode (c24f)` and `force feedback available`.
2. Unplug the wheel's USB cable, plug it back in, wait for the calibration
   spin, and rerun `check`; it must still report native mode.
3. Reboot with the wheel connected and rerun `check`.
4. Optional native test: open Oversteer, confirm steering, all three pedals,
   and buttons move, change range to 540° and back to 900°, and run its
   force-feedback test.
5. Forza: start Steam (once before and once after plugging in the wheel),
   launch Forza, and in its controls settings select the wheel. Verify:
   - steering covers the full rim rotation without dead zone or jitter;
   - throttle, brake, and clutch are independent axes, not combined;
   - force feedback is felt in corners and on collisions;
   - no duplicated controller or gamepad-only behavior.
6. If Forza sees no wheel or a duplicated gamepad, disable Steam Input for
   Forza only (Properties → Controller), retest, and report which setting
   worked. Include `./components/g29/g29.sh check` output with any failure.

## Logitech G923 Xbox edition

Install once (asks for sudo), with the wheel connected and hands off the rim:

```bash
./scripts/packages.sh install
./components/g923/g923.sh install
./components/g923/g923.sh check
```

1. Confirm `check` prints `PC mode (c26e)`, `logitech-hidpp driver` and
   `force feedback available`.
2. Unplug and replug the wheel's USB cable, then rerun `check`; it must still
   report PC mode.
3. Reboot with the wheel connected and rerun `check`.
4. Open Oversteer, confirm steering, all three pedals and buttons move,
   change range to 540° and back to 900°, and run its force-feedback test.
5. If `check` reports Xbox mode, include `./components/g923/g923.sh check`
   and `journalctl -b -u 'usb_modeswitch@*'` output.

## USB handbrake

```bash
./components/handbrake/handbrake.sh install   # sudo; first install also rebuilds the boot image
```

1. Unplug and replug the handbrake (or reboot after the first install), then
   run `./components/handbrake/handbrake.sh check`; every line must be `OK`,
   including `raw ... is hidden` and the `Omarchy USB Handbrake` joystick.
2. `evtest` on the listed virtual joystick: pulling moves `ABS_THROTTLE` and
   presses `BTN_TRIGGER` past half travel.
3. Restart Forza Horizon 5, open Settings → Controls → Handbrake remap, and
   pull the lever. It should register on a second device (axis or button) and
   lock the rear wheels in game. No launch options are needed.
