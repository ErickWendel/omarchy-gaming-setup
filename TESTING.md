# User verification: fast fixes

The latest real-machine results and the exact resume point are recorded in
[STATUS.md](STATUS.md). As of 2026-10-12, OpenRGB passed after reboot, Delta
still opened its desktop window, returning to Big Picture after a game was
dropped from scope, and PCSX2 worked with Steam Input disabled.

Apply the reviewed user-level configuration from a terminal:

```bash
cd ~/Downloads/projects/omarchy-gaming-setup
./scripts/apply-fast-fixes.sh
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

1. Run `systemctl --user restart delta-center.service`.
2. Confirm the cooler LCD resumes the saved display.
3. Confirm no Delta Center window opens automatically.
4. Open Delta Center from the application menu and confirm its UI still works.

## Steam Big Picture — issue #5

1. With no game running, press the PS button and confirm Big Picture opens.
2. Launch a Steam game (for example Forza) and confirm it opens in front.
3. Press PS in the game and confirm Steam's menu opens over the game and can
   be navigated with the controller.
4. Close the menu and confirm the game responds to the controller again.
5. Quit the game. Steam may drop to desktop mode; that is accepted. Pressing
   PS again must reopen Big Picture.

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
