# PCSX2: make both controllers work when launched through Steam

## Update — 2026-10-12

- The launcher forces XWayland (`QT_QPA_PLATFORM=xcb`); as a native Wayland
  window PCSX2 was invisible to Steam, which routed input to Big Picture.
- Steam Input stays disabled: with it enabled, Steam's overlay drew but could
  not take controller input in PCSX2's Qt/xcb window.
- `components/pcsx2/configure_pcsx2_ini.py` manages the Vulkan renderer and
  hotkeys: PS (sent as `Escape` by the helper) and Share + Options on any SDL
  slot open the pause menu; Share + R3 shuts down the game.
- A connected G29 takes `SDL-0`, making the PS5 pad player 2; other hotkeys
  and player mappings still follow `SDL-0`. Undecided whether to hide the
  wheel from PCSX2.

## Live verification — 2026-10-11

Partial pass: PCSX2 recognized the controller after Steam Input was manually
disabled. The installer has since applied that policy and the canonical local
wrapper to all nine detected PS2 shortcuts. Direct-launch parity, the second
controller, and the newly installed PS-button overlay fallback still require
explicit user verification before this issue can close.

## Summary

Make controller behavior identical whether PCSX2 is started directly, from an Omarchy application entry, from a Steam emulator shortcut, or from a PS2 game shortcut in Big Picture. Use one canonical wrapper and diagnose the Steam-specific input path before changing the already-present SDL/HIDAPI configuration.

## Evidence

- Controllers work when PCSX2 is opened directly but not when the same emulator is started through Steam.
- The existing PCSX2 launcher already exports `SDL_JOYSTICK_HIDAPI_PS4=0` and `SDL_JOYSTICK_HIDAPI_PS5=0`.
- The existing PCSX2 configuration already maps controllers as `SDL-0` and `SDL-1`.
- Because the direct launch works with those settings, the failure is likely specific to Steam's environment, Steam Input ownership/remapping, device permissions, or a different launch path/config directory. The implementation must verify which condition applies instead of adding duplicate mappings blindly.
- `GExtended` can become read-only, and launching PCSX2 must not depend on chmod, cleanup, or other writes to the emulator installation/content drive.

## Implementation

1. Establish one canonical PCSX2 wrapper.
   - Have Omarchy, the Steam emulator entry, and generated PS2 game entries call the same wrapper with the same PCSX2 binary and configuration directory.
   - Preserve the existing `SDL_JOYSTICK_HIDAPI_PS4=0` and `SDL_JOYSTICK_HIDAPI_PS5=0` exports unless diagnostics prove they are incorrect.
   - Preserve the existing `SDL-0`/`SDL-1` bindings; do not regenerate controller configuration on every launch.
   - Remove launcher-time chmod, deletion, or cleanup against `GExtended`; runtime logs/configuration must go to a writable user-state directory.
2. Add opt-in controller diagnostics to the wrapper.
   - Record the launch origin, resolved executable/config paths, relevant SDL/Steam environment variables, and enumerated controller names/GUIDs.
   - Record readable `/dev/input` nodes and current ACL/group access without logging account secrets or raw input events.
   - Make diagnostics bounded and disabled by default so normal launches remain quiet.
3. Verify host input prerequisites.
   - Confirm the distribution's `steam-devices`/udev rules package is installed and its rules are active.
   - Confirm the logged-in user/session receives access to the relevant `event` and `js` devices.
   - Verify both configured Sony controllers are visible before Steam starts, while Steam is running, and from the canonical wrapper's Steam-launched environment.
4. Reconcile Steam Input behavior for all generated PCSX2 entries.
   - Configure the emulator and generated PS2 game shortcuts to disable Steam Input for PCSX2 so Steam does not reserve or translate devices before SDL sees them.
   - Apply the policy consistently to new and existing project-managed shortcuts without changing controller policy for unrelated games.
   - Document the Steam UI fallback if the installed Steam version does not expose a stable configuration file/API for this per-shortcut setting.
5. Confirm launch parity.
   - Compare direct and Steam-launched diagnostic output to ensure they use the same wrapper, binary, config directory, environment overrides, and controller identities.
   - Treat controller enumeration order changes as an error because the current PCSX2 bindings target `SDL-0` and `SDL-1`; provide a clear remediation if stable GUID-based binding is supported by the installed PCSX2 version.

## Acceptance criteria

- Both configured controllers are detected and usable in PCSX2 when launched directly through the canonical wrapper.
- The same controllers and bindings work when PCSX2 is launched from its Omarchy entry, its non-Steam emulator shortcut, and a generated PS2 game shortcut in Big Picture.
- All four launch paths resolve the same PCSX2 executable and configuration directory.
- Steam Input is disabled for project-managed PCSX2/PS2 shortcuts, with no policy changes to unrelated Steam games.
- Existing `SDL_JOYSTICK_HIDAPI_PS4=0`, `SDL_JOYSTICK_HIDAPI_PS5=0`, `SDL-0`, and `SDL-1` settings remain intact unless captured diagnostics justify a reviewed migration.
- Launching performs no write, chmod, or cleanup operation on `GExtended`; a read-only game volume does not prevent controller initialization.
- Doctor output distinguishes missing udev rules, insufficient device ACLs, missing controllers, enumeration-order drift, and Steam interception.
- A regression checklist records results for each launch path with Steam Input on (diagnostic comparison) and off (required final behavior).

## Dependencies

- Depends on issue #6 for the canonical generated launcher and Steam shortcut reconciliation.
- Uses issue #2's storage probe so launch behavior does not assume a writable `GExtended` filesystem.
- Integrates with the setup/doctor framework from issue #1.
- Must complete before controller validation in issue #8.
