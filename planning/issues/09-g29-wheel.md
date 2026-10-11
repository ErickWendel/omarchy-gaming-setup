# Logitech G29: support the wheel reliably in PS4 mode

## Summary

Make the Logitech G29 wheel, pedals, force feedback, and optional shifter work
reliably on Omarchy while the wheel is set to PS4 mode. The physical PS3-mode
switch path is no longer usable, so the solution must not depend on PS3 mode.

Start by determining whether the in-kernel Logitech HID drivers already expose
the complete device in PS4 mode. Install or build an additional maintained
driver only when captured diagnostics prove that native support is incomplete.

## Evidence to collect

- Record `lsusb`, USB descriptors, kernel version, loaded modules, and relevant
  kernel log entries after connecting the wheel in PS4 mode.
- Record the bound kernel driver and every associated `hidraw`, `event`, and
  `js` node without capturing raw user input.
- Compare visibility and permissions outside Steam, while Steam is running,
  and inside a Steam-launched game.
- Test wheel axis range, pedals, buttons, shifter, centering, rotation range,
  gain, and force-feedback effects independently.
- Record whether Steam Input changes or hides the device and whether native
  Linux and Proton games behave differently.

## Implementation

1. Add a non-mutating `g29` doctor probe that identifies the wheel by USB
   vendor/product ID and confirms that it is operating in PS4 mode.
2. Verify native kernel support, `udev` permissions, session ACLs, and the
   installed `steam-devices` rules before changing drivers.
3. Evaluate maintained driver/configuration candidates, including the active
   kernel Logitech wheel driver and `new-lg4ff`, against the installed kernel.
   Document why an out-of-tree module is or is not necessary.
4. If native support is complete, version only the required udev and wheel
   configuration. Do not replace a working kernel driver.
5. If an out-of-tree driver is required:
   - pin a reviewed upstream revision and verify its source/checksum;
   - package it through DKMS so kernel upgrades rebuild it;
   - define module precedence explicitly and provide a safe uninstall path;
   - fail closed on unsupported kernels instead of leaving the wheel unbound.
6. Add a reproducible wheel configuration using a maintained Linux tool when
   needed for rotation range, gain, autocenter, and device-mode initialization.
   Do not commit per-game Steam account data.
7. Define Steam/Proton guidance per game. Prefer direct wheel passthrough and
   disable Steam Input only where testing shows that translation breaks the
   native wheel or force-feedback interface.
8. Add install, check, dry-run, rollback, and post-kernel-upgrade verification
   to the common setup framework.

## Safety requirements

- Do not flash wheel firmware or attempt to repair/bypass the physical mode
  switch as part of this issue.
- Do not download or run an unreviewed binary driver.
- Preserve a working in-kernel driver until the replacement module has passed
  build, load, bind, input, and force-feedback checks.
- Never grant broad world-writable access to all input or hidraw devices; udev
  rules must match the G29 specifically and use session-aware access.
- Every module override must have a documented rollback that works without the
  wheel connected.

## Acceptance criteria

- The G29 is detected after login and reconnect while physically set to PS4
  mode; PS3 mode is not required at any point.
- Wheel, pedals, buttons, and optional shifter expose stable input events with
  correct ranges and no stuck or duplicated axes.
- Centering, rotation range, gain, and representative force-feedback effects
  work in a native Linux test and at least one Steam/Proton driving game.
- The device works when Steam is started before or after the wheel is connected.
- Permissions are limited to the intended Logitech device and require no root
  game process.
- The selected driver survives a kernel upgrade, or the doctor reports a clear
  unsupported/rebuild state before games are launched.
- Setup is idempotent and uninstall restores the prior driver/module/udev state.

## Dependencies

- Uses the common install/check/backup interface from issue #1.
- Can be investigated in parallel with the existing service and storage issues.
- Must pass before the hardware portion of the final integration issue is done.

