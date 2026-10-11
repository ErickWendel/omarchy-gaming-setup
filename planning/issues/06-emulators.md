# Emulators: generate valid Omarchy and Steam application entries

## Summary

Make installed emulators discoverable as applications in Omarchy and as non-Steam entries in Steam. Generate both sets of launchers from one versioned emulator manifest, using the live `GExtended` mount discovered by UUID rather than assuming a block-device name or changing its mount location.

## Evidence

- Existing emulator `.desktop` files contain leading tab characters and are malformed enough that application discovery does not list them reliably.
- Emulator content is stored on the filesystem with UUID `1bae75c4-2c80-49ca-b1c0-7d5a0e819e95`.
- Its expected mount point on this machine remains `/run/media/erickwendel/GExtended`.
- The volume has been observed read-only after initially mounting read-write, so launcher/shortcut generation must honor the storage health gate from issue #2.
- Existing Steam emulator and ROM shortcuts may contain paths rooted at the current removable-media mount and must be reconciled rather than blindly duplicated.

## Implementation

1. Define a versioned emulator manifest as the single source for generated entries.
   - Include a stable ID, display name, executable or wrapper, icon, supported content location/category, and whether a Steam shortcut is required.
   - Keep machine-specific roots out of individual records; resolve the emulation root through the UUID-based storage probe.
   - Reject duplicate IDs and entries whose executable/wrapper cannot be resolved.
2. Generate standards-compliant desktop entries in the user's application directory.
   - Emit `[Desktop Entry]` at column zero with no leading whitespace or tabs.
   - Emit valid `Type`, `Name`, `Exec`, `Icon`, `Terminal`, and `Categories` fields; use `Game;Emulator;` categories and specification-compliant boolean values.
   - Quote or escape paths and arguments according to the Desktop Entry specification instead of shell-concatenating them.
   - Generate into a temporary location, run `desktop-file-validate`, then install atomically only after validation succeeds.
   - Remove only stale files owned by this project; do not modify unrelated desktop entries.
3. Refresh application discovery after successful generation using the desktop database and the supported Omarchy application-index refresh mechanism present on the installed system.
4. Reconcile Steam shortcuts.
   - Detect the applicable local Steam user/configuration without committing account identifiers.
   - Require Steam to be fully stopped before changing `shortcuts.vdf`; otherwise stop with instructions rather than killing Steam.
   - Back up `shortcuts.vdf` before the first change in a run and retain the original on parse/write failure.
   - Upsert shortcuts by a stable project-owned identity so reruns update entries without creating duplicates.
   - Preserve unrelated shortcuts and their metadata.
   - Use the canonical generated emulator wrapper and the UUID-resolved emulation root for emulator and ROM entries.
5. Add dry-run and check behavior.
   - Dry-run lists additions, updates, removals, missing executables/icons, and proposed Steam changes without writing.
   - Check mode validates installed desktop files, application discoverability inputs, shortcut targets, and storage availability.
   - If `GExtended` is absent or read-only, report the condition and avoid any operation requiring a drive write; desktop entries may only be installed when all referenced targets can be validated.

## Acceptance criteria

- Every managed `.desktop` file passes `desktop-file-validate` and contains no leading indentation before keys or section headers.
- Managed emulators appear in Omarchy's application launcher after refresh with the intended names and icons.
- Launching an entry invokes the configured wrapper/executable with paths under the UUID-resolved `/run/media/erickwendel/GExtended` mount.
- The corresponding emulator entries appear once in Steam and launch successfully; rerunning setup does not duplicate them.
- Existing unrelated non-Steam shortcuts remain byte-for-byte semantically intact, and a restorable backup is created before mutation.
- Setup refuses to edit `shortcuts.vdf` while Steam is running and refuses unsafe drive-dependent operations when issue #2 reports a read-only filesystem.
- Unit/fixture tests cover manifest validation, desktop-field escaping, idempotent shortcut upsert, preservation of unrelated shortcuts, and malformed existing desktop entries with leading tabs.

## Dependencies

- Depends on issue #2 for UUID-based mount discovery and the read-only/writability gate.
- Integrates with the setup framework from issue #1.
- Provides the canonical PCSX2/Steam launcher entry required by issue #7.
- Must complete before the emulator portion of issue #8.
