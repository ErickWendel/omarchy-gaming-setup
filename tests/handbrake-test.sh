#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/handbrake/handbrake.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo run >>"$LIMINE_LOG"' >"$fake_bin/limine-update"
printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >>"$UDEVADM_LOG"' >"$fake_bin/udevadm"
printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" >>"$SYSTEMCTL_LOG"' \
  '[[ $1 != is-active ]] || [[ -e $SERVICE_ACTIVE ]]' >"$fake_bin/systemctl"
chmod +x "$fake_bin/limine-update" "$fake_bin/udevadm" "$fake_bin/systemctl"

export PATH="$fake_bin:$PATH"
export LIMINE_LOG="$test_root/limine.log" UDEVADM_LOG="$test_root/udevadm.log"
export SYSTEMCTL_LOG="$test_root/systemctl.log" SERVICE_ACTIVE="$test_root/active"
export HANDBRAKE_SUDO=
export HANDBRAKE_SYSFS_ROOT="$test_root/sys"
export HANDBRAKE_DEV_ROOT="$test_root/dev"
export HANDBRAKE_CMDLINE="$test_root/cmdline"
export HANDBRAKE_DROPIN_DST="$test_root/etc/limine-entry-tool.d/omarchy-gaming-handbrake.conf"
export HANDBRAKE_RULE_DST="$test_root/etc/udev/rules.d/72-omarchy-handbrake-hide.rules"
export HANDBRAKE_LEGACY_RULE="$test_root/etc/udev/rules.d/70-omarchy-handbrake-hidraw.rules"
export HANDBRAKE_BRIDGE_DST="$test_root/usr/local/lib/omarchy-handbrake-bridge"
export HANDBRAKE_UNIT_DST="$test_root/etc/systemd/system/omarchy-handbrake-bridge.service"
fail() { echo "FAIL: $*" >&2; exit 1; }
count() { [[ -e $1 ]] && grep -c -- "$2" "$1" || echo 0; }

echo 'root=/dev/mapper/root quiet' >"$HANDBRAKE_CMDLINE"
handbrake="$HANDBRAKE_SYSFS_ROOT/bus/hid/devices/0003:046D:C219.0005"
mkdir -p "$handbrake" "$(dirname "$HANDBRAKE_LEGACY_RULE")"
echo '# old hidraw rule' >"$HANDBRAKE_LEGACY_RULE"

output=$("$script" check) && fail "check passed before installation"
grep -q 'drop-in missing' <<<"$output" || fail "missing drop-in not reported"
grep -q 'superseded rule still installed' <<<"$output" || fail "legacy rule not reported"
grep -q "bound to 'nothing'" <<<"$output" || fail "unbound handbrake not reported"
grep -q 'joystick not present' <<<"$output" || fail "missing virtual joystick not reported"

"$script" dry-run >/dev/null
[[ ! -e $HANDBRAKE_DROPIN_DST && ! -e $HANDBRAKE_RULE_DST && ! -e $HANDBRAKE_UNIT_DST ]] \
  || fail "dry-run installed files"

output=$("$script" install)
for pair in omarchy-gaming-handbrake.conf:$HANDBRAKE_DROPIN_DST \
            72-omarchy-handbrake-hide.rules:$HANDBRAKE_RULE_DST \
            omarchy-handbrake-bridge:$HANDBRAKE_BRIDGE_DST \
            omarchy-handbrake-bridge.service:$HANDBRAKE_UNIT_DST; do
  cmp -s "$repo_dir/components/handbrake/${pair%%:*}" "${pair#*:}" || fail "${pair%%:*} not installed"
done
[[ -x $HANDBRAKE_BRIDGE_DST ]] || fail "bridge not executable"
[[ ! -e $HANDBRAKE_LEGACY_RULE ]] || fail "legacy rule not removed"
[[ $(count "$LIMINE_LOG" run) == 1 ]] || fail "limine-update not run once"
grep -q 'enable omarchy-handbrake-bridge.service' "$SYSTEMCTL_LOG" || fail "service not enabled"
grep -q 'attr-match=idProduct=c219' "$UDEVADM_LOG" || fail "handbrake not re-triggered"
grep -q 'Reboot to apply' <<<"$output" || fail "reboot not requested"

"$script" install >/dev/null
[[ $(count "$LIMINE_LOG" run) == 1 ]] || fail "reinstall rebuilt the boot image"
[[ $(count "$SYSTEMCTL_LOG" restart) == 1 ]] || fail "reinstall restarted the service"

# After reboot: quirk active, raw nodes root-only, bridge running with its joystick.
echo 'root=/dev/mapper/root quiet usbhid.quirks=0x046d:0xc219:0x400000' >"$HANDBRAKE_CMDLINE"
mkdir -p "$HANDBRAKE_SYSFS_ROOT/bus/hid/drivers/hid-generic" "$handbrake/input/input10/event7" \
  "$handbrake/hidraw/hidraw4" "$HANDBRAKE_DEV_ROOT/input" "$HANDBRAKE_SYSFS_ROOT/class/input/input40/event27"
ln -s "$HANDBRAKE_SYSFS_ROOT/bus/hid/drivers/hid-generic" "$handbrake/driver"
echo 'Omarchy USB Handbrake' >"$HANDBRAKE_SYSFS_ROOT/class/input/input40/name"
: >"$HANDBRAKE_DEV_ROOT/input/event27"
: >"$SERVICE_ACTIVE"
output=$("$script" check) || fail "check failed after reboot: $output"
grep -q 'raw .*/input/event7 is hidden' <<<"$output" || fail "hidden event node not reported"
grep -q 'joystick is .*/input/event27' <<<"$output" || fail "virtual joystick not reported"

# A raw node visible to the user means games still see the gamepad.
: >"$HANDBRAKE_DEV_ROOT/input/event7"
output=$("$script" check) && fail "check passed with a visible raw node"
grep -q 'still visible' <<<"$output" || fail "visible raw node not reported"

"$script" uninstall >/dev/null
for path in "$HANDBRAKE_DROPIN_DST" "$HANDBRAKE_RULE_DST" "$HANDBRAKE_BRIDGE_DST" "$HANDBRAKE_UNIT_DST"; do
  [[ ! -e $path ]] || fail "$path not removed"
done
grep -q 'disable --now omarchy-handbrake-bridge.service' "$SYSTEMCTL_LOG" || fail "service not disabled"
[[ $(count "$LIMINE_LOG" run) == 2 ]] || fail "uninstall did not rebuild the boot image"

echo "handbrake tests passed"
