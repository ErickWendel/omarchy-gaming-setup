#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wrapper="$repo_dir/components/nfsmw/nfsmw-wheel-wrapper"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

devices="$test_root/devices"
bridge="$test_root/bridge"
# Stand-in bridge: announces the virtual wheel, then runs until killed.
cat >"$bridge" <<EOF
#!/usr/bin/env bash
trap 'echo stopped >"$test_root/bridge.state"; exit 0' TERM
echo running >"$test_root/bridge.state"
echo 'N: Name="Omarchy NFS Wheel"' >"$devices"
while :; do sleep 0.05; done
EOF
chmod +x "$bridge"
: >"$devices"
mkdir -p "$test_root/sys/bus/hid/devices"
export NFSMW_SYSFS_ROOT="$test_root/sys" NFSMW_INPUT_DEVICES="$devices" NFSMW_WHEEL_BRIDGE="$bridge"
export XDG_STATE_HOME="$test_root/state" SDL_GAMECONTROLLER_IGNORE_DEVICES='0x28de/0x1002,0x28de/0x1003,'

# No G923: no bridge, environment untouched, exit status kept.
out=$("$wrapper" bash -c 'echo "$SDL_GAMECONTROLLER_IGNORE_DEVICES"; exit 3') && fail "exit status lost" || [[ $? == 3 ]] || fail "exit status lost"
[[ $out == '0x28de/0x1002,0x28de/0x1003,' ]] || fail "ignore list changed without a wheel: $out"
[[ ! -e $test_root/bridge.state ]] || fail "bridge started without a wheel"

# G923 connected: bridge runs during the game, the real wheel is hidden, the bridge stops after.
mkdir -p "$test_root/sys/bus/hid/devices/0003:046D:C26E.000A"
out=$("$wrapper" bash -c 'echo "$SDL_GAMECONTROLLER_IGNORE_DEVICES $(<"$1")"' _ "$test_root/bridge.state")
[[ $out == '0x28de/0x1002,0x28de/0x1003,0x046d/0xc26e running' ]] || fail "wheel mode: $out"
[[ $(<"$test_root/bridge.state") == stopped ]] || fail "bridge left running"
grep -q '^wheel mode: G923 bridged' "$test_root/state/nfsmw-wheel-wrapper.log" || fail "wheel mode not logged"

# Empty ignore list: no stray comma.
out=$(SDL_GAMECONTROLLER_IGNORE_DEVICES= "$wrapper" bash -c 'echo "$SDL_GAMECONTROLLER_IGNORE_DEVICES"')
[[ $out == 0x046d/0xc26e ]] || fail "empty ignore list: $out"

# A bridge that never shows the virtual wheel leaves the real one visible.
printf '#!/bin/sh\nexit 1\n' >"$bridge"; : >"$devices"
out=$("$wrapper" bash -c 'echo "$SDL_GAMECONTROLLER_IGNORE_DEVICES"')
[[ $out == '0x28de/0x1002,0x28de/0x1003,' ]] || fail "real wheel hidden without a bridge: $out"
echo "nfsmw wrapper tests passed"
