# Storage: check and repair GExtended in place

## Summary

Detect when the `GExtended` ext4 filesystem is read-only, unhealthy or
misplaced, keep setup from depending on it in that state, and repair it in
place with `e2fsck`. Files stay where they are: no staging copy, no reformat,
no repartitioning. The filesystem UUID and the desktop-session mount point
`/run/media/erickwendel/GExtended` do not change.

This replaces the earlier plan to copy the volume to another disk, reformat it
and restore it. The evidence below does not show filesystem damage that
would need that, and the copy would take hours for no gain.

## Evidence

- Filesystem UUID: `1bae75c4-2c80-49ca-b1c0-7d5a0e819e95`, mounted at
  `/run/media/erickwendel/GExtended` with
  `rw,nosuid,nodev,relatime,errors=remount-ro`.
- The mount was earlier observed turning `ro`; the block device itself never
  reported write protection.
- 2026-10-24: ext4's superblock error record is empty (`errors_count=0` in
  `/sys/fs/ext4/sda1`), and the kernel logs kept for this boot and the last
  show no I/O errors, resets or remounts for the disk.
- The drive is a bus-powered Toshiba MQ04UBF100 (USB `0480:0905`, 896 mA)
  connected through a USB 3.2 hub at 5 Gb/s. It offers only Bulk-Only
  transport (no UAS), so `usb-storage` is the right driver. Sequential reads
  measured about 91 MB/s, which is near what this 2.5" 5400 rpm disk can do;
  the USB link is not the limit.
- Likely cause of the earlier read-only flips: brief power or link loss on
  the hub, which makes ext4 (`errors=remount-ro`) remount read-only. Not yet
  proven by a captured log.

## Implementation

1. `scripts/storage.sh check`, used by `./setup.sh --check`:
   - resolve the partition by UUID (`/dev/disk/by-uuid`), never by `/dev/sdX`;
   - report distinct states with distinct exit codes and messages: absent (2),
     unmounted (3), read-only (4), not writable by the user (5), mounted at
     the wrong path (6), ext4 errors recorded (7), healthy (0);
   - test writability with a probe file only on a read-write mount, and
     remove it;
   - report the USB link (speed, driver, hub) as notes.
2. `scripts/storage.sh diagnose`: `check` plus `findmnt`/`lsblk` identity,
   the ext4 error record, kernel messages for the disk and SMART through
   `smartctl -d sat` when installed. Read only.
3. `scripts/storage.sh fsck`: in-place repair, run only by hand.
   - Unmount with `udisksctl`; stop if the mount is busy.
   - Run `e2fsck -fn` (no changes). Clean: mount again and finish.
   - Problems found: require the user to type `REPAIR`, then `e2fsck -fp`.
     If `e2fsck` needs answers, leave the disk unmounted and print the
     interactive command.
   - `e2fsck` failure or declined repair: mount again unchanged.
   - Mount again with `udisksctl` and rerun `check`.
4. Setup never runs `fsck`, unmounts, remounts or formats. No setup module
   writes to `GExtended` today; any future one must run `storage.sh check`
   first.
5. Hardware: move the drive from the hub to a USB 3 port on the PC; install
   `smartmontools` and review `diagnose` once.

## Acceptance criteria

- `check` resolves the UUID, reports the mount point and options, and returns
  the exit code for each state above; a healthy run leaves no probe file.
- A read-only mount fails `check` without any write or remount.
- `fsck` never runs `e2fsck` on a mounted filesystem, never changes the
  filesystem without the typed `REPAIR`, and keeps the UUID and mount point.
- Automated tests (`tests/storage-test.sh`) cover absent, unmounted,
  read-write, read-only, permission-denied, wrong mount point, recorded ext4
  errors, clean fsck, declined repair, confirmed repair, repair needing
  manual answers, failed `e2fsck` and busy mount.
- Verified on the real disk: `check` passes, and one `fsck` run with Steam
  closed reports clean or repairs and returns the disk read-write at
  `/run/media/erickwendel/GExtended`.

## Dependencies

- Can be implemented independently.
- Unblocks the write-dependent parts of #6 and the end-to-end check in #8.
