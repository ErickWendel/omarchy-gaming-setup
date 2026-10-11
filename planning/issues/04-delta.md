# Delta Center: start the LCD controller hidden as a user service

## Live verification — 2026-10-11

Failed after a full reboot: the Delta desktop window still opened after login,
despite the legacy XDG autostart entry being disabled and the installed user
unit invoking `delta-center-launch --hidden`. The issue remains open. The next
step is to determine whether the managed process owns the visible window,
another startup path exists, or this Delta/Electron runtime ignores `--hidden`.
See `STATUS.md` for the evidence commands and resume point.

## Problem

Delta Center opens its interface after login, although only its background LCD-controller process should start automatically.

The installed `~/.config/autostart/delta-center.desktop` currently runs:

```text
~/.local/opt/delta-center/delta-center-launch
```

without `--hidden`. This differs from the existing `delta-cw360lcd-linux-driver` installer, which generates an XDG autostart command ending in `delta-center-launch --hidden`. The installed launcher also adds the Linux/Electron compatibility flags and must remain the canonical executable entry point.

## Required outcome

Replace Delta's login autostart entry with one systemd user service attached to `graphical-session.target`. It must execute `delta-center-launch --hidden`, restore the LCD controller after login without opening the interface, and leave the normal application-menu launcher available for opening the UI on demand.

## Implementation notes

- Install a `delta-center.service` user unit under `~/.config/systemd/user/` with:
  - `PartOf=graphical-session.target` and `After=graphical-session.target`;
  - `ExecStart=%h/.local/opt/delta-center/delta-center-launch --hidden`;
  - `Restart=on-failure` and a bounded restart delay;
  - no system/root privileges.
- Enable the unit for `graphical-session.target`, reload the user manager, and start/restart it when setup is run from a live graphical session. If there is no graphical session, only enable it for the next login.
- Remove or disable `~/.config/autostart/delta-center.desktop` through the common backup mechanism so XDG autostart and systemd cannot launch duplicate instances.
- Preserve `~/.local/share/applications/delta-center.desktop` with its non-hidden command; this remains the intentional way to show the application UI.
- Update the source installer in `delta-cw360lcd-linux-driver` so future installs produce the same user-service configuration instead of recreating an XDG autostart entry. Keep `--hidden` explicit even though the source installer already emits it today.
- Keep the proprietary Delta archive/runtime outside this repository. The umbrella setup may accept a local archive path, install it into `~/.local/opt/delta-center`, and verify that `delta-center-launch` is executable before enabling the service.
- Add checks for runtime/launcher presence, service enablement and activity, the `--hidden` argument, duplicate startup entries, and the retained application-menu launcher.

## Safety requirements

- Do not commit the Delta archive, extracted runtime, private binaries, or generated app data.
- Do not delete or overwrite an installed runtime merely to configure startup. Back up replaced unit, autostart, launcher, and desktop files using the shared backup mechanism.
- Do not enable or start the service unless `delta-center-launch` exists and is executable. On failure, report the missing archive/runtime input without blocking unrelated setup components.
- Do not run Delta Center as root. Existing privileged USB/udev installation remains a separate, explicit step and is not part of service startup.
- Stop the old instance before switching startup mechanisms, then start exactly one managed instance. Avoid killing unrelated Electron processes.
- A failed migration must not leave both the old autostart entry and the new enabled service active.

## Acceptance criteria

- After a fresh graphical login, Delta Center controls/restores the LCD without showing its main window.
- `systemctl --user is-enabled delta-center.service` succeeds and the service is associated with `graphical-session.target`.
- The running service command includes `delta-center-launch --hidden` and there is only one Delta Center instance.
- The old `~/.config/autostart/delta-center.desktop` is no longer active.
- The application-menu entry still opens/shows Delta Center manually without creating a competing background controller instance.
- `./setup.sh --check` reports the runtime/launcher, unit state, hidden argument, duplicate-startup state, and desktop launcher.
- Running setup twice is idempotent and does not duplicate units, entries, processes, or backups.
- A missing private runtime marks only the Delta component as skipped/failed with remediation instructions; unrelated components continue.

## Dependencies

- Depends on the foundation issue for common backup, service-install, local-archive input, dry-run, and check behavior.
- Requires the Delta driver's existing launcher/runtime and its USB permission setup to be installed before end-to-end hardware verification.
- Does not depend on storage, OpenRGB, Steam, or emulator work and can be implemented in parallel with those components.
