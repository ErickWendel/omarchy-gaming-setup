# User verification: fast fixes

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

1. Start Steam and enter Big Picture with the PS button.
2. Launch one game, then close the game normally.
3. Confirm Big Picture returns exactly once.
4. Minimize Big Picture and wait at least 15 seconds.
5. Confirm it stays minimized and does not reopen itself.

## PCSX2 controllers — issue #7

1. Connect both Sony controllers before starting Steam.
2. Start one PS2 game from its existing Steam shortcut.
3. Confirm both controllers work in PCSX2 using the existing player mappings.
4. While the game is running, press the PS button and confirm Steam's in-game
   menu opens even though Steam Input is disabled for the shortcut.
5. Close the game and launch PCSX2 directly with
   `~/.local/bin/omarchy-pcsx2`; confirm both controllers still work.
6. If either path fails, run
   `~/.local/bin/omarchy-pcsx2 --omarchy-diagnose` and include its output.
