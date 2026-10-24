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
export G923_OPTIONS_DST="$test_root/etc/modprobe.d/logitech-trueforce.conf"
export G923_PACKAGE_RULE="$test_root/usr/lib/udev/rules.d/73-logitech-xbox-modeswitch.rules"
export G923_PACKAGE_MODESWITCH="$test_root/usr/bin/logi-wheel-modeswitch"
export G923_USB_MODESWITCH="$test_root/usr/bin/usb_modeswitch"
export G923_INITRAMFS_TOOL="$test_root/usr/bin/logi-wheel-initramfs"
export INITRAMFS_LOG="$test_root/initramfs.log"
export OMARCHY_BACKUP_ROOT="$test_root/backups"
fail() { echo "FAIL: $*" >&2; exit 1; }
executable() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n%s\n' "${2:-}" >"$1"; chmod +x "$1"; }

# Install refuses to run without usb_modeswitch or the package's mode switch.
"$script" install >/dev/null 2>&1 && fail "install succeeded without usb_modeswitch"
executable "$G923_USB_MODESWITCH"
"$script" install >/dev/null 2>&1 && fail "install succeeded without logitech-trueforce-dkms"
mkdir -p "$(dirname "$G923_PACKAGE_RULE")"; echo '# package rule' >"$G923_PACKAGE_RULE"
executable "$G923_PACKAGE_MODESWITCH"
executable "$G923_INITRAMFS_TOOL" 'echo "$*" >>"$INITRAMFS_LOG"'

# A wheel in Xbox mode is a plain USB device, reported as a failure.
xbox="$G923_SYSFS_ROOT/bus/usb/devices/3-10.4"
mkdir -p "$xbox" "$G923_SYSFS_ROOT/bus/hid/devices"
echo 046d >"$xbox/idVendor"; echo c26d >"$xbox/idProduct"
output=$("$script" check) && fail "check passed without installation"
grep -q 'FAIL G923: hid-logitech-dd options missing' <<<"$output" || fail "missing options not reported"
grep -q 'still in Xbox mode' <<<"$output" || fail "Xbox mode not reported"
grep -q 'OK   G923: Xbox-mode switch installed by logitech-trueforce-dkms' <<<"$output" || fail "package switch not reported"

# dry-run must not touch the destination files.
"$script" dry-run >/dev/null
[[ ! -e $G923_OPTIONS_DST ]] || fail "dry-run installed files"

# The rule and config an earlier version installed: the config replaced a
# previous one (backed up then), the rule was new.
mkdir -p "$(dirname "$G923_CONFIG_DST")" "$(dirname "$G923_RULE_DST")" \
  "$(dirname "$OMARCHY_BACKUP_ROOT/system$G923_CONFIG_DST")" "$(dirname "$OMARCHY_BACKUP_ROOT/system$G923_RULE_DST")"
echo '# old managed config' >"$G923_CONFIG_DST"
echo '# previous config' >"$OMARCHY_BACKUP_ROOT/system$G923_CONFIG_DST"
echo '# old managed rule' >"$G923_RULE_DST"
: >"$OMARCHY_BACKUP_ROOT/system$G923_RULE_DST.absent"
output=$("$script" check) && fail "check passed with the old rule installed"
grep -q "old Xbox-mode file still installed: $G923_RULE_DST" <<<"$output" || fail "old rule not reported"

# Install removes them, installs the options and triggers the connected wheel.
"$script" install >/dev/null
[[ ! -e $G923_RULE_DST ]] || fail "old rule not removed"
grep -qx '# previous config' "$G923_CONFIG_DST" || fail "previous config not restored"
[[ ! -e $OMARCHY_BACKUP_ROOT/system$G923_RULE_DST.absent ]] || fail "old rule backup marker kept"
cmp -s "$repo_dir/components/g923/logitech-trueforce.conf" "$G923_OPTIONS_DST" || fail "options not installed"
grep -qx -- '--force' "$INITRAMFS_LOG" || fail "initramfs not regenerated for new options"
grep -q "trigger --action=add $xbox" "$UDEVADM_LOG" || fail "wheel not triggered"
rm -f "$G923_CONFIG_DST"

# Second install is idempotent and leaves the initramfs alone.
"$script" install >/dev/null
[[ $(wc -l <"$INITRAMFS_LOG") == 1 ]] || fail "initramfs regenerated for unchanged options"

# The switched wheel passes the device checks.
echo c26e >"$xbox/idProduct"
pc="$G923_SYSFS_ROOT/devices/usb3/3-10.4/3-10.4:1.0/0003:046D:C26E.000C"
mkdir -p "$pc/input/input40/capabilities" "$G923_SYSFS_ROOT/bus/hid/drivers/logitech-dd"
ln -s "$pc" "$G923_SYSFS_ROOT/bus/hid/devices/0003:046D:C26E.000C"
ln -s "$G923_SYSFS_ROOT/bus/hid/drivers/logitech-dd" "$pc/driver"
echo 00 >"$pc/../bInterfaceNumber"
echo 900 >"$pc/range"
# Interface 1 is bound too but has no input or range; check must skip it.
second="$G923_SYSFS_ROOT/devices/usb3/3-10.4/3-10.4:1.1/0003:046D:C26E.000D"
mkdir -p "$second"; echo 01 >"$second/../bInterfaceNumber"
ln -s "$second" "$G923_SYSFS_ROOT/bus/hid/devices/0003:046D:C26E.000D"
ln -s "$G923_SYSFS_ROOT/bus/hid/drivers/logitech-dd" "$second/driver"
echo 30000 >"$pc/input/input40/capabilities/ff"
echo 'Logitech G923 Racing Wheel for Xbox One and PC' >"$pc/input/input40/name"
# The driver's own force engine must be on.
params="$G923_SYSFS_ROOT/module/hid_logitech_dd/parameters"
mkdir -p "$params"; echo N >"$params/g923_xbox_dd_engine"
output=$("$script" check) && fail "check passed with the force engine off"
grep -q 'force engine off' <<<"$output" || fail "engine off not reported"
echo Y >"$params/g923_xbox_dd_engine"
output=$("$script" check) || fail "check failed for a PC-mode wheel: $output"
grep -q 'PC mode (c26e)' <<<"$output" || fail "PC mode not reported"
grep -q 'bound to the logitech-dd driver' <<<"$output" || fail "driver not reported"
grep -q 'force feedback available' <<<"$output" || fail "force feedback not reported"

# Uninstall removes the options and leaves the package's rule alone.
"$script" uninstall >/dev/null
[[ ! -e $G923_OPTIONS_DST ]] || fail "options not removed"
[[ -e $G923_PACKAGE_RULE ]] || fail "package rule touched"
[[ $(wc -l <"$INITRAMFS_LOG") == 2 ]] || fail "initramfs not regenerated on uninstall"

echo "g923 tests passed"
