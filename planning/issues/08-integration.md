# Integration: verify one-script restore and idempotency

## Goal

Prove that a fresh Omarchy installation can restore the supported gaming setup with one safe, repeatable setup command, and that diagnostics clearly identify any manual prerequisite such as a missing private Delta archive, disconnected hardware, or a read-only emulation disk.

## Implementation notes

- Wire the completed component modules into the repository's top-level setup command and its `--dry-run` and `--check` modes.
- Run installation twice against the same machine state; the second run must make no unnecessary changes, create no duplicate services or launchers, and preserve user configuration.
- Verify that OpenRGB and Delta use exactly one startup mechanism each, their user services have the intended graphical-session behavior, and Delta remains hidden at login.
- Verify generated emulator desktop entries with `desktop-file-validate`, refresh/discover them through Omarchy's application index, and confirm their executable and icon targets resolve.
- Verify Steam helper installation/version pinning, the Big Picture lifecycle tests, emulator/ROM shortcut reconciliation, and safe handling when Steam must be stopped before shortcut edits.
- Verify PCSX2 controller discovery for direct, emulator-shortcut, and Steam Big Picture launches, including both configured controllers and required `/dev/input` access.
- Verify the Logitech G29 in PS4 mode, including axes, pedals, buttons, optional shifter, rotation settings, and force feedback in native and Steam/Proton paths.
- Detect `GExtended` by UUID or label at its existing mount location and report absent or read-only states without attempting filesystem repair.
- Produce a concise doctor report covering disk health/writability, OpenRGB profile/service, Delta service, Steam helper, desktop entries, Steam shortcuts, and PCSX2 input.
- Document the recovery flow: clone the repository, satisfy reported manual prerequisites, provide the private Delta archive when available, run setup, log in or reboot as instructed, and run `--check`.

## Privacy and safety requirements

- Never commit or upload ROMs, proprietary Delta binaries or archives, Steam userdata/account data, credentials, generated logs containing personal data, or device-specific secrets.
- Exercise ignore rules in an automated check using representative filenames and directories.
- Back up user-owned files before replacement and do not perform filesystem repair automatically.
- A missing optional/private component must block or skip only that component; unrelated modules must remain installable and checkable.

## Dependencies

- Blocked by the foundation, storage, OpenRGB, Delta, Steam Big Picture, emulator discovery, PCSX2 controller, and G29 wheel issues.
- Component repositories must have their required changes published at immutable commits or releases before the final restore test.

## Test scenarios

- Fresh Omarchy installation with `GExtended` healthy but initially unmounted.
- Existing installation with legacy or malformed desktop entries and old generated Steam shortcuts.
- `GExtended` absent or mounted read-only: setup stops only dependent writes and reports remediation without changing the mount path.
- OpenRGB and Delta hardware connected and disconnected at login.
- Game exit returns to Big Picture once; a later manual minimize remains minimized.
- Emulator entries appear in Omarchy and Steam after setup.
- Both configured controllers work in PCSX2 when launched directly, from an emulator entry, and from Steam Big Picture.
- The Logitech G29 works in PS4 mode without relying on its broken PS3-mode switch path.
- Missing Delta archive does not prevent OpenRGB, Steam, emulator, storage diagnostics, or controller setup from completing.
- Two consecutive full setup runs converge to the same configuration.

## Acceptance criteria

- A documented top-level command restores every available component and a second run is idempotent.
- `--dry-run` describes intended changes without modifying user configuration.
- `--check` exits nonzero for actionable failures and prints component-level pass, skip, or fail results.
- Service validation confirms enabled/running state, single-startup ownership, and correct visible/hidden behavior.
- Desktop and Steam application validation confirms emulator discovery without corrupting existing shortcuts.
- Controller validation confirms both configured pads through all three PCSX2 launch paths.
- Wheel validation confirms G29 inputs and force feedback through native and Steam/Proton paths in PS4 mode.
- Automated checks confirm prohibited private/account artifacts are absent from Git history and the working tree.
- The final doctor report is sufficient to distinguish setup defects from missing hardware, private artifacts, filesystem health, or user-session prerequisites.
