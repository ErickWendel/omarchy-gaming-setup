# Foundation: implement the idempotent Omarchy setup framework

## Summary

Turn the current non-mutating setup contract into a modular, idempotent
installer for this workstation. A second run must reconcile state without
duplicating services, entries, or configuration.

## Implementation

- Add component modules for storage guard, OpenRGB, Delta, Steam, emulators,
  and PCSX2 under a shared install/check/backup interface.
- Preserve `--check`, `--dry-run`, and `--delta-archive PATH`.
- Back up every replaced user file and show privileged operations before sudo.
- Let missing optional hardware block only its component.
- Pin external component revisions and verify downloaded release checksums.
- Keep filesystem repair manual and never edit `/usr/share/omarchy`.

## Acceptance criteria

- `./setup.sh --dry-run` performs no writes.
- `./setup.sh --check` returns nonzero and explains each failed invariant.
- Two consecutive successful installs produce no duplicate configuration.
- ShellCheck passes and automated tests exercise option parsing and backups.
- Private/vendor payloads and Steam account data cannot be accidentally added.

## Dependencies

None. This defines the interface consumed by the component issues.

