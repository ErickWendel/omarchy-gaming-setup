#!/usr/bin/env bash
# GExtended games disk: check|diagnose|fsck.
#
#   check     report the disk's state; exits nonzero unless it is mounted
#             read-write at GEXTENDED_MOUNT, writable and free of ext4 errors
#   diagnose  check, plus device identity, kernel messages and SMART (read only)
#   fsck      repair in place: unmount through udisks, run a read-only
#             e2fsck, and only after typing REPAIR let e2fsck fix what it
#             found; then mount it again through udisks
#
# Files stay where they are: nothing is copied, moved, reformatted or
# repartitioned, and the filesystem UUID and mount point do not change.
# check and diagnose never unmount, remount or write anything but a probe
# file that is removed straight away.
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ -z ${GEXTENDED_UUID:-} ]]; then
  config_file="$repo_dir/config/machine.env"
  [[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
  # shellcheck source=../config/machine.example.env
  set -a; source "$config_file"; set +a
fi

action=${1:-check}
uuid=$GEXTENDED_UUID
expected_mount=$GEXTENDED_MOUNT
by_uuid_dir=${STORAGE_BY_UUID_DIR:-/dev/disk/by-uuid}
sysfs_root=${STORAGE_SYSFS_ROOT:-/sys}
sudo_cmd=${STORAGE_SUDO-sudo}

say() { printf '%s\n' "$*"; }
ok() { printf 'OK   %s\n' "$*"; }
note() { printf 'NOTE %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
die() { printf 'ERROR GExtended: %s\n' "$*" >&2; exit 1; }

# Exit codes of check, so callers can tell the states apart.
readonly ST_OK=0 ST_ABSENT=2 ST_UNMOUNTED=3 ST_READ_ONLY=4 ST_NOT_WRITABLE=5 \
  ST_WRONG_MOUNT=6 ST_FS_ERRORS=7

device= devname= target= options=

# Resolve the partition by filesystem UUID, never by /dev/sdX name.
resolve_device() {
  device= devname= target= options=
  [[ -e $by_uuid_dir/$uuid ]] || return 1
  device=$(readlink -f -- "$by_uuid_dir/$uuid")
  devname=${device##*/}
  read -r target options < <(findmnt -rn -S "$device" -o TARGET,OPTIONS 2>/dev/null | head -n1)
  return 0
}

# Create and remove a probe file; only meaningful on a read-write mount.
write_probe() {
  local probe
  probe=$(mktemp -p "$target" .omarchy-write-probe.XXXXXX 2>/dev/null) || return 1
  rm -f -- "$probe"
}

# ext4 keeps its error count in the superblock and shows it in sysfs.
fs_error_count() {
  local file=$sysfs_root/fs/ext4/$devname/errors_count
  [[ -r $file ]] && cat -- "$file" || echo 0
}

# Describe the USB link: interface driver, negotiated speed, and whether the
# drive sits behind an external hub. A bus-powered drive on a hub can lose
# power under load, and ext4 (errors=remount-ro) then turns the mount
# read-only. Hub chips built into the motherboard (removable=fixed) are how
# the board provides its own ports, so they are not reported.
link_report() {
  local dir driver= speed= hub=
  dir=$(readlink -f -- "$sysfs_root/class/block/$devname" 2>/dev/null) || return 0
  while [[ $dir == "$sysfs_root"/* ]]; do
    if [[ -z $driver && -e $dir/bInterfaceClass && -L $dir/driver ]]; then
      driver=$(basename -- "$(readlink -- "$dir/driver")")
    elif [[ -z $speed && -r $dir/speed && -r $dir/idVendor ]]; then
      speed=$(<"$dir/speed")
      local parent=${dir%/*}
      [[ ${parent##*/} != usb* && -r $parent/bDeviceClass && $(<"$parent/bDeviceClass") == 09 &&
         $(cat -- "$parent/removable" 2>/dev/null) != fixed ]] && hub=$(<"$parent/product")
      break
    fi
    dir=${dir%/*}
  done
  [[ -n $speed ]] || { note "GExtended is not a USB drive; no link check"; return 0; }
  note "GExtended USB link: ${speed} Mb/s, driver ${driver:-unknown}"
  ((speed >= 5000)) || warn "GExtended runs below USB 3 speed; plug it into a USB 3 (blue/SS) port"
  [[ -z $hub ]] || note "GExtended is connected through an external hub ($hub); a port on the PC avoids power drops"
}

check() {
  if ! resolve_device; then
    warn "GExtended ($uuid) is not connected; plug the disk in"
    return "$ST_ABSENT"
  fi
  if [[ -z $target ]]; then
    warn "GExtended is at $device but not mounted; open it in the file manager or run: udisksctl mount -b $device"
    return "$ST_UNMOUNTED"
  fi
  ok "GExtended ($device) is mounted at $target ($options)"
  link_report
  if [[ ,$options, != *,rw,* ]]; then
    warn "GExtended at $target is read-only; nothing will write to it. Repair in place: $0 fsck"
    return "$ST_READ_ONLY"
  fi
  if [[ $target != "$expected_mount" ]]; then
    warn "GExtended is mounted at $target, expected $expected_mount; unmount it and mount it again from the file manager"
    return "$ST_WRONG_MOUNT"
  fi
  if ! write_probe; then
    warn "GExtended at $target is read-write but $USER cannot create files there; check its ownership (ls -ld $target)"
    return "$ST_NOT_WRITABLE"
  fi
  ok "GExtended is read-write and writable"
  local errors
  errors=$(fs_error_count)
  if ((errors > 0)); then
    warn "GExtended's ext4 has recorded $errors error(s) ($sysfs_root/fs/ext4/$devname); repair in place: $0 fsck"
    return "$ST_FS_ERRORS"
  fi
  ok "GExtended's ext4 has no recorded errors"
  return "$ST_OK"
}

diagnose() {
  local status parent f
  check; status=$?
  [[ -n $device ]] || return "$status"
  parent=$(lsblk -no PKNAME "$device" 2>/dev/null | head -n1)
  say
  say "-- Device"
  findmnt -S "$device" -o SOURCE,TARGET,FSTYPE,OPTIONS 2>/dev/null
  lsblk -o NAME,SIZE,TRAN,MODEL,SERIAL,FSTYPE,LABEL,UUID "/dev/${parent:-$devname}" 2>/dev/null
  say
  say "-- ext4 error record"
  for f in errors_count first_error_time first_error_func last_error_time last_error_func; do
    [[ -r $sysfs_root/fs/ext4/$devname/$f ]] && printf '%s=%s\n' "$f" "$(<"$sysfs_root/fs/ext4/$devname/$f")"
  done
  say
  say "-- Kernel messages for ${parent:-$devname} (this boot and the last)"
  { journalctl -k -b -1 --no-pager 2>/dev/null; journalctl -k -b 0 --no-pager 2>/dev/null; } |
    grep -E "(${parent:-$devname}|$devname)\b|EXT4-fs|usb-storage|uas" |
    grep -iE "error|fail|reset|disconnect|read-only|remount|EXT4-fs \($devname\)" | tail -n 40
  say
  say "-- SMART"
  if command -v smartctl >/dev/null 2>&1; then
    $sudo_cmd smartctl -a -d sat "/dev/${parent:-$devname}" ||
      note "smartctl could not read this USB bridge; try: sudo smartctl -a /dev/${parent:-$devname}"
  else
    note "smartctl is missing; install smartmontools for the disk's health report"
  fi
  return "$status"
}

fsck_in_place() {
  local rc answer
  resolve_device || die "GExtended ($uuid) is not connected"
  say "GExtended: $device (UUID $uuid)"
  if [[ -n $target ]]; then
    say "Unmounting $target; close Steam, emulators and file managers that use it first"
    udisksctl unmount -b "$device" ||
      die "could not unmount $target; see what uses it with: fuser -vm $target"
  fi

  say "Checking without changing anything: e2fsck -fn $device"
  $sudo_cmd e2fsck -fn "$device"; rc=$?
  if ((rc == 0)); then
    say "The filesystem is clean."
  elif ((rc == 4)); then
    say
    say "e2fsck found problems. Fixing them changes this filesystem in place; it is not backed up."
    printf 'Type REPAIR to let e2fsck fix %s: ' "$device"
    read -r answer || answer=
    if [[ $answer != REPAIR ]]; then
      say "Not repaired. Mounting it again unchanged."
      udisksctl mount -b "$device" >/dev/null || warn "mount it again from the file manager"
      return 1
    fi
    $sudo_cmd e2fsck -fp "$device"; rc=$?
    if ((rc >= 4)); then
      die "e2fsck needs answers it will not guess; run it yourself and answer each prompt: sudo e2fsck -f $device"
    fi
    say "Repaired."
  else
    udisksctl mount -b "$device" >/dev/null || true
    die "e2fsck could not check $device (exit $rc); the filesystem was not changed"
  fi

  udisksctl mount -b "$device" >/dev/null || die "could not mount $device again; open it in the file manager"
  check
}

case "$action" in
  check) check ;;
  diagnose) diagnose ;;
  fsck) fsck_in_place ;;
  *) say "Usage: $0 check|diagnose|fsck" >&2; exit 2 ;;
esac
