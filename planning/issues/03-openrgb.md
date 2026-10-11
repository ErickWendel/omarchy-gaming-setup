# OpenRGB: reliably apply `static-green` after graphical login

## Problem

OpenRGB does not reliably start at login or apply the saved lighting profile.

The current machine has the profile at `~/.config/OpenRGB/static-green.orp`. Its OpenRGB configuration names `static-green` as the autostart profile, but `AutoStart.setprofile` is `false`. The only login hook is `~/.config/autostart/OpenRGB.desktop`, whose command is:

```text
/usr/bin/openrgb --startminimized
```

That command starts the GUI minimized but does not explicitly load the profile. Startup also depends on an XDG autostart entry, with no useful restart or delayed-device handling.

## Required outcome

Install one systemd user service, attached to `graphical-session.target`, that starts OpenRGB minimized and explicitly loads `static-green.orp`. Disable the old XDG autostart path so only one OpenRGB instance is launched. The setup must be repeatable and suitable for restoring the same behavior on a fresh Omarchy installation.

## Implementation notes

- Add a versioned copy of `static-green.orp` to this repository and install it to `~/.config/OpenRGB/static-green.orp`. Treat the profile as configuration, not as generated runtime state.
- Install an `openrgb.service` user unit under `~/.config/systemd/user/` with:
  - `PartOf=graphical-session.target` and `After=graphical-session.target`;
  - an `ExecStart` equivalent to `/usr/bin/openrgb --startminimized --profile %h/.config/OpenRGB/static-green.orp`;
  - a short bounded startup delay or retry strategy for RGB devices that appear shortly after login;
  - `Restart=on-failure` with a bounded restart delay, while avoiding an unlimited tight loop.
- Enable the unit for `graphical-session.target`, reload the user manager, and start/restart it when setup is run inside a live graphical session.
- Remove or disable `~/.config/autostart/OpenRGB.desktop` after backing it up through the repository's common backup mechanism. Re-running setup must not create duplicate backups or startup entries.
- Add component checks for the OpenRGB binary, installed profile, enabled unit, active process, and absence of the old active XDG autostart entry.
- When the graphical session is unavailable during installation, enable the service but defer its start until the next graphical login.

## Safety requirements

- Do not invoke OpenRGB I2C/SMBus tooling or alter hardware-level bus settings. OpenRGB explicitly warns that unsafe I2C operations can damage hardware.
- Do not replace the user's profile without preserving the previous file. A failed install must leave either the previous working profile/startup path or the new complete configuration, not a partial mixture.
- Do not run multiple OpenRGB instances. Stop the service before replacing its unit/profile, then use a daemon reload and a single restart.
- If `/usr/bin/openrgb` or the source profile is missing, report an actionable error and leave the existing startup configuration untouched.

## Acceptance criteria

- After a fresh graphical login, exactly one OpenRGB process is running and no main window is shown.
- `static-green.orp` is explicitly loaded at startup; lighting matches the saved static-green profile without manual interaction.
- `systemctl --user is-enabled openrgb.service` succeeds and the service is associated with `graphical-session.target`.
- The prior `OpenRGB.desktop` autostart entry is no longer active, so it cannot launch a second instance.
- `./setup.sh --check` reports the binary, profile, unit enablement, process state, and duplicate-startup status.
- Running setup twice produces the same configuration and leaves only one startup mechanism.
- With RGB hardware temporarily unavailable at login, the service does not spin in a tight restart loop and can recover once hardware is available or after one manual restart.

## Dependencies

- Depends on the foundation issue for shared backup, install, dry-run, and check helpers.
- Does not depend on storage, Delta, Steam, or emulator work and can be implemented in parallel with those components.

