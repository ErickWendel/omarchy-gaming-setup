# Storage: repair and reformat GExtended through verified local staging

## Summary

Determine why the `GExtended` ext4 filesystem changes from read-write to read-only, protect dependent setup operations from the unhealthy mount, and repair it through a verified local staging-and-restore workflow. The migration must prove the backup is complete before requesting permission to reformat and must retain the staged copy until the restored filesystem is independently verified.

Keep the existing desktop-session mount location. This issue must not introduce an `/etc/fstab` entry or migrate the drive to `/mnt`.

## Evidence

- Filesystem UUID: `1bae75c4-2c80-49ca-b1c0-7d5a0e819e95`.
- Expected current mount point: `/run/media/erickwendel/GExtended`.
- The filesystem was observed mounting read-write initially and later appearing with `ro,nosuid,nodev,relatime,errors=remount-ro`.
- A directory write check failed while the mount was read-only.
- The block device itself did not report a hardware read-only state, so the observed transition is at the filesystem or mount layer.
- Emulator launchers and Steam shortcuts currently refer to content on this volume; some launcher behavior also attempts writes there.
- The volume hosts Linux gaming and emulator assets, including launchers/AppImages that require Unix executable bits and permissions.

## Implementation

1. Add a storage probe used by both setup and doctor modes.
   - Resolve the device by filesystem UUID, not by `/dev/sdX` name.
   - Find the active mount point from the resolved device and confirm it equals `/run/media/erickwendel/GExtended` when mounted.
   - Report these states distinctly: device absent, present but unmounted, mounted read-write, and mounted read-only.
   - Test effective writability with a temporary file only when the mount reports read-write; clean up the probe file on success and failure.
2. Diagnose the filesystem, physical disk, and connection before proposing repair.
   - Include the current `findmnt` source, target, filesystem type, and options.
   - Include the UUID-to-device resolution and relevant recent kernel messages for the resolved block device/ext4 filesystem when permissions allow.
   - Capture the physical device model, serial, transport, partition layout, and complete SMART report using `smartctl` when supported.
   - Classify media errors, pending/reallocated sectors, uncorrectable errors, failed SMART health, link resets, and SATA UDMA CRC errors separately. CRC/link errors require cable/port/power inspection and a clean retest; media-health failures require replacing the disk.
   - Clearly distinguish a permissions failure, filesystem corruption, a failing disk, and a suspected cable/port problem.
   - Do not format when SMART/media diagnostics indicate a failing disk or when connection errors continue after reseating/replacing the cable or port. In those cases, stop and recommend recovery to a healthy replacement device.
3. Gate dependent operations and the repair workflow.
   - Setup must skip or fail before any emulator, launcher, or Steam-shortcut operation that would write to `GExtended`.
   - The failure message must preserve the detected device and mount point and explain the safe next stage.
   - Never automatically run `fsck`, unmount, format, remount read-write, or modify partition/mount configuration from the normal setup path.
4. Preflight a local staging destination before copying.
   - Require an explicit staging path on a healthy local filesystem located on a different physical device from `GExtended`; reject paths on the source device, network mounts, and temporary filesystems.
   - Measure source apparent size and allocated size, destination available bytes/inodes, and reserve at least the larger source measurement plus 10% free-space headroom on the destination.
   - Refuse to continue when capacity, inode availability, destination writability, or destination filesystem health cannot be established.
   - Record source device identity, filesystem UUID, mount options, file/byte counts, and the selected staging path in a timestamped migration manifest.
5. Create and verify the staged local copy without modifying the source.
   - Build a deterministic SHA-256 inventory of all regular files, including relative path and size, before copying. Record symlinks, permissions, ownership, timestamps, ACLs, extended attributes, hard links, and empty directories separately so restoration can preserve them.
   - Copy with a metadata-preserving tool such as `rsync -aHAX --numeric-ids`, while remaining readable on a source that is already mounted read-only.
   - Generate a fresh SHA-256 inventory from the staged files and compare it with the source inventory; also compare file, directory, symlink, and byte counts.
   - Stop on unreadable source data, checksum mismatch, metadata-copy failure, or count mismatch. Preserve the partial staging data and logs for retry; do not advance to unmount or format.
6. Require a destructive-operation checkpoint.
   - Close Steam, emulators, shells, and file-manager windows using the source, then verify no process has the mount open.
   - Re-resolve the UUID immediately before the checkpoint and display the exact partition path, parent-disk model/serial/capacity, current filesystem UUID/label, verified staging path, inventory digest, and verification timestamp.
   - Require the user to type an explicit confirmation containing the resolved partition path and the word `FORMAT`. A generic yes/no flag, unattended mode, or prior setup consent is insufficient.
   - Abort if device identity changed, staging verification is stale or missing, the partition is still busy, or health diagnostics are no longer clean.
7. Recreate the filesystem for Linux gaming use.
   - Unmount the verified source partition and format that partition only; never repartition the disk or infer the target from `/dev/sdX` naming.
   - Use ext4 with label `GExtended`. Prefer normal, broadly supported ext4 defaults (extents, 64-bit support, metadata checksums and journaling as supplied by the installed `mkfs.ext4`) rather than experimental features or tuning that reduces recoverability.
   - Preserve executable bits, Unix permissions, symlinks, ACLs, and xattrs; do not use `noexec`. Use the normal udisks desktop mount behavior (`rw,nosuid,nodev,relatime`) for compatibility and sensible performance.
   - Record the newly generated filesystem UUID in the machine configuration and migration manifest because formatting replaces the prior UUID. Do not retain the old UUID by force.
8. Remount, restore, and independently verify.
   - Remount through the normal desktop/udisks flow and verify that the resulting path is `/run/media/erickwendel/GExtended`, the mount is read-write, and executable files can retain and exercise their execute bit.
   - Restore from staging with metadata preservation, then build a third SHA-256 inventory from the restored destination and compare it to the verified staging inventory plus all recorded object/byte counts.
   - Run filesystem, launcher/AppImage execute-bit, emulator-content readability, and representative game-library checks before declaring success.
   - Keep the staging directory, original and restored inventories, SMART output, command logs, and migration manifest until the user explicitly confirms the applications and restored data are working.
9. Provide rollback and recovery paths.
   - Before formatting, rollback means remounting the untouched source through the normal desktop flow and retaining/removing the staged copy only at the user's direction.
   - After formatting, never attempt to reconstruct from the old filesystem in place; recovery must resume from the verified staging copy, allowing an idempotent restore retry after correcting mount/capacity/permission failures.
   - If formatting or restore fails, leave the staging copy untouched, report the last completed checkpoint, and provide exact next-step commands using the recorded partition identity.
10. Make the mount path configurable internally while retaining `/run/media/erickwendel/GExtended` as this machine's expected value. Downstream code should consume the probe result and recorded post-format UUID rather than reconstructing or hard-coding a `/dev/sdX` path.

## Acceptance criteria

- Before migration, the probe resolves current UUID `1bae75c4-2c80-49ca-b1c0-7d5a0e819e95`; after formatting, it resolves the newly recorded UUID. In both cases it reports the active mount point and options.
- A healthy read-write mount passes both the mount-option and temporary-file checks without leaving a file behind.
- A read-only mount produces a non-zero check result and blocks all dependent writes without attempting repair or remounting.
- Device-absent, unmounted, read-only, and permission-denied results have different actionable messages.
- Diagnostics capture ext4/kernel and SMART/link evidence and block formatting for a failing disk or unresolved cable/port errors.
- Staging preflight proves the destination is on another healthy local physical device and has the required bytes, inodes, writability, and 10% headroom.
- Source and staged SHA-256 inventories, object counts, byte counts, and preserved metadata match before any destructive prompt is shown.
- Formatting cannot start without a fresh identity/health/busy-state check and typed confirmation naming the exact partition plus `FORMAT`.
- The recreated filesystem is ext4 labeled `GExtended`, uses broadly compatible options without `noexec`, receives a new recorded UUID, and returns at `/run/media/erickwendel/GExtended`.
- Source, staging, and restored inventories match; representative executable/AppImage and emulator-content checks pass on the restored volume.
- An interrupted or failed restore can be rerun from the untouched verified staging copy, and artifacts are retained until explicit user sign-off.
- No code or documentation changes the canonical mount point away from `/run/media/erickwendel/GExtended`.
- Automated tests cover parsed fixtures for read-write, read-only, unmounted, absent-device, permission-denied, insufficient staging capacity, same-device staging, checksum mismatch, busy mount, changed target identity, blocked unhealthy hardware, and resumable restore states.

## Dependencies

- Can be implemented independently.
- The common setup/doctor command contract from issue #1 should be used when available; this issue may define a small probe interface for issue #1 to adopt.
- Blocks the write-dependent portions of issue #6 and the end-to-end validation in issue #8.
