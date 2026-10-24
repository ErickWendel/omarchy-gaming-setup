#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'chmod -R u+w -- "$test_root"; rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
sysfs="$test_root/sys"
by_uuid="$test_root/by-uuid"
mount_dir="$test_root/media/GExtended"
log="$test_root/commands.log"
uuid=1bae75c4-2c80-49ca-b1c0-7d5a0e819e95
mkdir -p "$fake_bin" "$by_uuid" "$mount_dir" "$sysfs/fs/ext4/sda1" "$sysfs/class/block"
: >"$test_root/sda1"

# A drive behind the motherboard's own USB 3 hub chip, the way GExtended is
# connected on this machine.
hub="$sysfs/devices/pci0000:80/usb4/4-8"
drive="$hub/4-8.4"
iface="$drive/4-8.4:1.0"
block="$iface/host8/target8:0:0/8:0:0:0/block/sda/sda1"
mkdir -p "$block" "$sysfs/bus/usb/drivers/usb-storage"
printf '09\n' >"$hub/bDeviceClass"; printf 'USB3.2 Hub\n' >"$hub/product"; printf 'fixed\n' >"$hub/removable"
printf '5000\n' >"$hub/speed"; printf '0bda\n' >"$hub/idVendor"
printf '5000\n' >"$drive/speed"; printf '0480\n' >"$drive/idVendor"
printf '08\n' >"$iface/bInterfaceClass"
ln -s "$sysfs/bus/usb/drivers/usb-storage" "$iface/driver"
ln -s "$block" "$sysfs/class/block/sda1"
printf '0\n' >"$sysfs/fs/ext4/sda1/errors_count"

# findmnt prints "$FAKE_TARGET $FAKE_OPTIONS" while the fake disk is mounted.
cat >"$fake_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
[[ -e $FAKE_STATE/mounted ]] && printf '%s %s\n' "$FAKE_TARGET" "$FAKE_OPTIONS"
exit 0
EOF
cat >"$fake_bin/udisksctl" <<'EOF'
#!/usr/bin/env bash
echo "udisksctl $*" >>"$FAKE_LOG"
case $1 in
  unmount) [[ ${FAKE_BUSY:-0} == 1 ]] && exit 1; rm -f "$FAKE_STATE/mounted" ;;
  mount) touch "$FAKE_STATE/mounted" ;;
esac
EOF
# e2fsck exits with $FAKE_CHECK_RC for -fn and $FAKE_REPAIR_RC for -fp.
cat >"$fake_bin/e2fsck" <<'EOF'
#!/usr/bin/env bash
echo "e2fsck $*" >>"$FAKE_LOG"
[[ -e $FAKE_STATE/mounted ]] && { echo "e2fsck ran on a mounted filesystem" >&2; exit 99; }
case $1 in
  -fn) exit "${FAKE_CHECK_RC:-0}" ;;
  -fp) exit "${FAKE_REPAIR_RC:-1}" ;;
esac
exit 99
EOF
chmod +x "$fake_bin"/*

export PATH="$fake_bin:$PATH" FAKE_STATE="$test_root" FAKE_LOG="$log"
export GEXTENDED_UUID=$uuid GEXTENDED_MOUNT=$mount_dir
export STORAGE_BY_UUID_DIR=$by_uuid STORAGE_SYSFS_ROOT=$sysfs STORAGE_SUDO=
export FAKE_TARGET=$mount_dir FAKE_OPTIONS=rw,nosuid,nodev,relatime,errors=remount-ro
storage="$repo_dir/scripts/storage.sh"

expect_check() {
  local want=$1 pattern=$2 out rc=0
  out=$("$storage" check 2>&1) || rc=$?
  [[ $rc == "$want" ]] || { printf 'check exited %s, want %s:\n%s\n' "$rc" "$want" "$out" >&2; exit 1; }
  grep -q -- "$pattern" <<<"$out" || { printf 'missing "%s" in:\n%s\n' "$pattern" "$out" >&2; exit 1; }
}

# Device absent, then present but unmounted.
expect_check 2 'not connected'
ln -s ../sda1 "$by_uuid/$uuid"
expect_check 3 'not mounted'

# Healthy read-write mount: passes, leaves no probe file, and does not call
# the motherboard's hub chip a hub.
touch "$test_root/mounted"
expect_check 0 'read-write and writable'
expect_check 0 'USB link: 5000 Mb/s, driver usb-storage'
! "$storage" check | grep -q 'hub'
test -z "$(ls -A "$mount_dir")"

# The same chip in an external hub is reported.
printf 'removable\n' >"$hub/removable"
expect_check 0 'through an external hub (USB3.2 Hub)'
printf 'fixed\n' >"$hub/removable"

# Read-only mount fails before any write is attempted.
FAKE_OPTIONS=ro,nosuid,nodev,relatime,errors=remount-ro expect_check 4 'read-only'
chmod a-w "$mount_dir"
FAKE_OPTIONS=ro,nosuid,nodev,relatime expect_check 4 'storage.sh fsck'

# Read-write mount the user cannot write to (root can write anywhere).
if ((EUID != 0)); then expect_check 5 'cannot create files'; fi
chmod u+w "$mount_dir"

# Mounted somewhere else.
FAKE_TARGET="$test_root/elsewhere" expect_check 6 "expected $mount_dir"

# ext4 recorded errors.
printf '3\n' >"$sysfs/fs/ext4/sda1/errors_count"
expect_check 7 'recorded 3 error'
printf '0\n' >"$sysfs/fs/ext4/sda1/errors_count"

# fsck on a clean filesystem: unmounts, checks read-only, mounts again.
: >"$log"
"$storage" fsck </dev/null >/dev/null
test -e "$test_root/mounted"
diff <(printf '%s\n' "udisksctl unmount -b $test_root/sda1" "e2fsck -fn $test_root/sda1" "udisksctl mount -b $test_root/sda1") "$log"

# fsck with problems, declined: nothing repaired, mounted again unchanged.
: >"$log"
if FAKE_CHECK_RC=4 "$storage" fsck <<<"no" >/dev/null; then echo "declined repair succeeded" >&2; exit 1; fi
! grep -q -- '-fp' "$log"
test -e "$test_root/mounted"

# fsck with problems, confirmed: repairs in place and mounts again.
: >"$log"
FAKE_CHECK_RC=4 "$storage" fsck <<<"REPAIR" >/dev/null
grep -qx "e2fsck -fp $test_root/sda1" "$log"
test -e "$test_root/mounted"

# Repair that needs manual answers leaves the disk unmounted.
: >"$log"
if FAKE_CHECK_RC=4 FAKE_REPAIR_RC=4 "$storage" fsck <<<"REPAIR" >/dev/null 2>&1; then
  echo "unfinished repair succeeded" >&2; exit 1
fi
test ! -e "$test_root/mounted"
touch "$test_root/mounted"

# e2fsck itself failed: no repair, mounted again.
: >"$log"
if FAKE_CHECK_RC=8 "$storage" fsck </dev/null >/dev/null 2>&1; then echo "failed check succeeded" >&2; exit 1; fi
! grep -q -- '-fp' "$log"
test -e "$test_root/mounted"

# Busy mount: unmount fails and e2fsck never runs.
: >"$log"
if FAKE_BUSY=1 "$storage" fsck </dev/null >/dev/null 2>&1; then echo "busy fsck succeeded" >&2; exit 1; fi
! grep -q e2fsck "$log"

echo "storage tests passed"
