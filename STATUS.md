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
| Steam Big Picture (#5) | Fail | Closing a game still exits Big Picture instead of returning to it. |
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

## Next investigation: Steam Big Picture

The lifecycle tests pass, but the live observations used to arm restoration do
not match this Steam session. Reproduce one launch-and-close cycle, then collect:

```bash
systemctl --user status ps5-steam-big-picture.service --no-pager
journalctl -t ps5-steam-big-picture -b --no-pager -n 100
hyprctl clients -j
pgrep -af 'steam|gameoverlayui|gamescope|pcsx2'
```

Capture `hyprctl clients -j` once while Big Picture is visible, once while the
game is running, and once immediately after it closes. The likely next change
is to use the observed Steam window identity and actual game process lifecycle
instead of relying only on the current title markers plus
`gameoverlayui`/`gamescope` process names. Retain the one-shot disarm behavior
so a later manual minimize cannot reopen Big Picture.

## Remaining user verification

- During a Steam-launched PCSX2 game, press PS and verify that Steam's overlay
  opens through the installed `Shift+Tab` fallback.
- Launch PCSX2 directly through `~/.local/bin/omarchy-pcsx2` and verify both
  controllers still work.
- After the Steam lifecycle fix changes, repeat the return-once and
  stay-minimized-for-15-seconds checks in `TESTING.md`.

## Repository publication

The umbrella, Delta, and Steam-helper repositories contain local commits that
were not pushed during this session because the execution environment could
not resolve `github.com`. Push them before updating or closing GitHub issues.
