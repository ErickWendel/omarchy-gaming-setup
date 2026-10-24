#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/g923/g923.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' "$*" >>"$UDEVADM_LOG"' >"$fake_bin/udevadm"
chmod +x "$fake_bin/udevadm"

export PATH="$fake_bin:$PATH"
export UDEVADM_LOG="$test_root/udevadm.log"
export G923_SUDO=
export G923_SYSFS_ROOT="$test_root/sys"
export G923_CONFIG_DST="$test_root/etc/usb_modeswitch.d/046d:c26d"
export G923_RULE_DST="$test_root/etc/udev/rules.d/41-omarchy-g923-xbox-mode.rules"
export G923_MODESWITCH_HELPER="$test_root/usr/lib/udev/usb_modeswitch"
export OMARCHY_BACKUP_ROOT="$test_root/backups"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Install refuses to run without the usb_modeswitch package.
"$script" install >/dev/null 2>&1 && fail "install succeeded without usb_modeswitch"
mkdir -p "$(dirname "$G923_MODESWITCH_HELPER")"
printf '#!/bin/sh\n' >"$G923_MODESWITCH_HELPER"; chmod +x "$G923_MODESWITCH_HELPER"

# A wheel in Xbox mode is a plain USB device, reported as a failure.
xbox="$G923_SYSFS_ROOT/bus/usb/devices/3-10.4"
mkdir -p "$xbox" "$G923_SYSFS_ROOT/bus/hid/devices"
echo 046d >"$xbox/idVendor"; echo c26d >"$xbox/idProduct"
output=$("$script" check) && fail "check passed without installation"
grep -q 'FAIL G923: usb_modeswitch config missing' <<<"$output" || fail "missing config not reported"
grep -q 'still in Xbox mode' <<<"$output" || fail "Xbox mode not reported"

# dry-run must not touch the destination files.
"$script" dry-run >/dev/null
[[ ! -e $G923_RULE_DST && ! -e $G923_CONFIG_DST ]] || fail "dry-run installed files"

# A pre-existing config is backed up, then the connected wheel is triggered.
mkdir -p "$(dirname "$G923_CONFIG_DST")"
echo '# previous config' >"$G923_CONFIG_DST"
"$script" install >/dev/null
cmp -s "$repo_dir/components/g923/046d:c26d" "$G923_CONFIG_DST" || fail "config not installed"
cmp -s "$repo_dir/components/g923/41-omarchy-g923-xbox-mode.rules" "$G923_RULE_DST" || fail "rule not installed"
grep -qx '# previous config' "$OMARCHY_BACKUP_ROOT/system$G923_CONFIG_DST" || fail "previous config not backed up"
grep -q "trigger --action=add $xbox" "$UDEVADM_LOG" || fail "wheel not triggered"

# Second install is idempotent and keeps the original backup.
"$script" install >/dev/null
grep -qx '# previous config' "$OMARCHY_BACKUP_ROOT/system$G923_CONFIG_DST" || fail "backup overwritten"

# The switched wheel passes the device checks.
echo c26e >"$xbox/idProduct"
pc="$G923_SYSFS_ROOT/devices/usb3/3-10.4/3-10.4:1.0/0003:046D:C26E.000C"
mkdir -p "$pc/input/input40/capabilities" "$G923_SYSFS_ROOT/bus/hid/drivers/logitech-hidpp-device"
ln -s "$pc" "$G923_SYSFS_ROOT/bus/hid/devices/0003:046D:C26E.000C"
ln -s "$G923_SYSFS_ROOT/bus/hid/drivers/logitech-hidpp-device" "$pc/driver"
echo 00 >"$pc/../bInterfaceNumber"
echo 900 >"$pc/range"
# Interface 1 is bound too but has no input or range; check must skip it.
second="$G923_SYSFS_ROOT/devices/usb3/3-10.4/3-10.4:1.1/0003:046D:C26E.000D"
mkdir -p "$second"; echo 01 >"$second/../bInterfaceNumber"
ln -s "$second" "$G923_SYSFS_ROOT/bus/hid/devices/0003:046D:C26E.000D"
ln -s "$G923_SYSFS_ROOT/bus/hid/drivers/logitech-hidpp-device" "$second/driver"
echo 30000 >"$pc/input/input40/capabilities/ff"
echo 'Logitech G923 Racing Wheel for Xbox One and PC' >"$pc/input/input40/name"
output=$("$script" check) || fail "check failed for a PC-mode wheel: $output"
grep -q 'PC mode (c26e)' <<<"$output" || fail "PC mode not reported"
grep -q 'force feedback available' <<<"$output" || fail "force feedback not reported"

# Uninstall restores the previous config and removes the rule.
"$script" uninstall >/dev/null
grep -qx '# previous config' "$G923_CONFIG_DST" || fail "previous config not restored"
[[ ! -e $G923_RULE_DST ]] || fail "rule not removed"

echo "g923 tests passed"
