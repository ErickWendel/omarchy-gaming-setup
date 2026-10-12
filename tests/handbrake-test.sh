#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/handbrake/handbrake.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo run >>"$LIMINE_LOG"' >"$fake_bin/limine-update"
chmod +x "$fake_bin/limine-update"

export PATH="$fake_bin:$PATH"
export LIMINE_LOG="$test_root/limine.log"
export HANDBRAKE_SUDO=
export HANDBRAKE_SYSFS_ROOT="$test_root/sys"
export HANDBRAKE_CMDLINE="$test_root/cmdline"
export HANDBRAKE_DROPIN_DST="$test_root/etc/limine-entry-tool.d/omarchy-gaming-handbrake.conf"
fail() { echo "FAIL: $*" >&2; exit 1; }
runs() { [[ -e $LIMINE_LOG ]] && wc -l <"$LIMINE_LOG" || echo 0; }

echo 'root=/dev/mapper/root quiet' >"$HANDBRAKE_CMDLINE"
unbound="$HANDBRAKE_SYSFS_ROOT/bus/hid/devices/0003:046D:C219.0005"
mkdir -p "$unbound"

output=$("$script" check) && fail "check passed before installation"
grep -q 'drop-in missing' <<<"$output" || fail "missing drop-in not reported"
grep -q "bound to 'nothing'" <<<"$output" || fail "unbound handbrake not reported"

"$script" dry-run >/dev/null
[[ ! -e $HANDBRAKE_DROPIN_DST ]] || fail "dry-run installed the drop-in"

output=$("$script" install)
cmp -s "$repo_dir/components/handbrake/omarchy-gaming-handbrake.conf" "$HANDBRAKE_DROPIN_DST" || fail "drop-in not installed"
[[ $(runs) == 1 ]] || fail "limine-update not run once"
grep -q 'Reboot to apply' <<<"$output" || fail "reboot not requested"

"$script" install >/dev/null
[[ $(runs) == 1 ]] || fail "reinstall rebuilt the boot image"

# After reboot: quirk on the command line and hid-generic bound.
echo 'root=/dev/mapper/root quiet usbhid.quirks=0x046d:0xc219:0x400000' >"$HANDBRAKE_CMDLINE"
mkdir -p "$HANDBRAKE_SYSFS_ROOT/bus/hid/drivers/hid-generic" "$unbound/input/input10"
ln -s "$HANDBRAKE_SYSFS_ROOT/bus/hid/drivers/hid-generic" "$unbound/driver"
echo 'game handbrake' >"$unbound/input/input10/name"
output=$("$script" check) || fail "check failed after reboot: $output"
grep -q 'bound to hid-generic' <<<"$output" || fail "hid-generic binding not reported"

"$script" uninstall >/dev/null
[[ ! -e $HANDBRAKE_DROPIN_DST ]] || fail "drop-in not removed"
[[ $(runs) == 2 ]] || fail "uninstall did not rebuild the boot image"

echo "handbrake tests passed"
