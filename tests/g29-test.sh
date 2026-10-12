#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/g29/g29.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' "$*" >>"$UDEVADM_LOG"' >"$fake_bin/udevadm"
chmod +x "$fake_bin/udevadm"

export PATH="$fake_bin:$PATH"
export UDEVADM_LOG="$test_root/udevadm.log"
export G29_SUDO=
export G29_SYSFS_ROOT="$test_root/sys"
export G29_HELPER_DST="$test_root/usr/local/lib/g29-ps4-modeswitch"
export G29_RULE_DST="$test_root/etc/udev/rules.d/71-omarchy-g29-ps4-mode.rules"
export OMARCHY_BACKUP_ROOT="$test_root/backups"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Mirror sysfs: HID devices are symlinks into their USB interface directory.
add_hid() {
  local interface=$1 name=$2 parent="$G29_SYSFS_ROOT/devices/usb3/3-10.2/3-10.2:1.${1}"
  mkdir -p "$parent/$name" "$G29_SYSFS_ROOT/bus/hid/devices"
  echo "0$interface" >"$parent/bInterfaceNumber"
  ln -sfn "$parent/$name" "$G29_SYSFS_ROOT/bus/hid/devices/$name"
  printf '%s\n' "$parent/$name"
}

# A wheel in PS4 mode is reported as a failure before installation.
ps4=$(add_hid 0 0003:046D:C260.0006)
mkdir -p "$ps4/hidraw/hidraw4"
output=$("$script" check) && fail "check passed without installation"
grep -q 'FAIL G29: mode-switch helper missing' <<<"$output" || fail "missing helper not reported"
grep -q 'still in PS4 mode' <<<"$output" || fail "PS4 mode not reported"

# dry-run must not touch the destination files.
"$script" dry-run >/dev/null
[[ ! -e $G29_RULE_DST && ! -e $G29_HELPER_DST ]] || fail "dry-run installed files"

# A pre-existing rule is backed up, then the connected wheel is triggered.
mkdir -p "$(dirname "$G29_RULE_DST")"
echo '# previous rule' >"$G29_RULE_DST"
"$script" install >/dev/null
cmp -s "$repo_dir/components/g29/71-omarchy-g29-ps4-mode.rules" "$G29_RULE_DST" || fail "rule not installed"
[[ -x $G29_HELPER_DST ]] || fail "helper not installed"
grep -qx '# previous rule' "$OMARCHY_BACKUP_ROOT/system$G29_RULE_DST" || fail "previous rule not backed up"
grep -q "trigger --action=add $G29_SYSFS_ROOT/class/hidraw/hidraw4" "$UDEVADM_LOG" || fail "wheel not triggered"

# Second install is idempotent and keeps the original backup.
"$script" install >/dev/null
grep -qx '# previous rule' "$OMARCHY_BACKUP_ROOT/system$G29_RULE_DST" || fail "backup overwritten"

# The switched wheel passes the device checks.
rm -rf "$ps4" "$G29_SYSFS_ROOT/bus/hid/devices/0003:046D:C260.0006"
native=$(add_hid 0 0003:046D:C24F.000A)
add_hid 1 0003:046D:C24F.000B >/dev/null  # unbound second interface must be ignored
mkdir -p "$native/input/input32/capabilities" "$G29_SYSFS_ROOT/bus/hid/drivers/logitech"
ln -s "$G29_SYSFS_ROOT/bus/hid/drivers/logitech" "$native/driver"
echo 900 >"$native/range"; echo 65535 >"$native/gain"; echo 0 >"$native/autocenter"
echo 31fff0000 >"$native/input/input32/capabilities/ff"
echo 'Logitech G29 Driving Force Racing Wheel' >"$native/input/input32/name"
output=$("$script" check) || fail "check failed for a native wheel: $output"
grep -q 'native mode (c24f)' <<<"$output" || fail "native mode not reported"
grep -q 'force feedback available' <<<"$output" || fail "force feedback not reported"

# Uninstall restores the previous rule and removes the helper.
"$script" uninstall >/dev/null
grep -qx '# previous rule' "$G29_RULE_DST" || fail "previous rule not restored"
[[ ! -e $G29_HELPER_DST ]] || fail "helper not removed"

echo "g29 tests passed"
