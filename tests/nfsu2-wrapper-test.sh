#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wrapper="$repo_dir/components/nfsu2/nfsu2-wheel-wrapper"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

game="$test_root/games/Need for Speed - Underground 2"
scripts="$game/scripts"
wheel="$test_root/sys/bus/hid/devices/0003:046D:C24F.0001"
proton="$test_root/proton/proton"
mkdir -p "$scripts" "$wheel" "$(dirname "$proton")/files/bin" "$test_root/compat/pfx"
echo 0 >"$wheel/combine_pedals"
printf 'ImproveGamepadSupport = 2                ; Adds text\n' >"$scripts/NFSUnderground2.WidescreenFix.ini"
touch "$scripts/ffb.asi" "$scripts/NFSU2SplitScreen.asi" "$scripts/modupdater.asi.off"
cat >"$game/ffb.ini" <<'EOF'
steer = {9E573EDF-7734-11D2-8D4A-23903FB6BDF7}|X|0|65535
throttle = {9E573EDF-7734-11D2-8D4A-23903FB6BDF7}|Z|32639|983
handbrake = {9E573EDE-7734-11D2-8D4A-23903FB6BDF7}|X|1966|63569
seq_device = {9E573EDF-7734-11D2-8D4A-23903FB6BDF7} ; comment
EOF
# Stand-in Wine: prints the dinput trace lines the probe parses.
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
dev() { echo "0024:trace:dinput:hid_joystick_enum_device found device L\"\\\\\\\\?\\\\hid#vid_$1&pid_$2#x\", usage 0001:0004, product {x}, instance {$3}, name L\"x\"" >&2; }
dev 046d c24f 9e573eda-7734-11d2-8d4a-23903fb6bdf7
dev 1209 4842 9e573ed2-7734-11d2-8d4a-23903fb6bdf7
exec sleep 30
EOF
printf '#!/bin/sh\n' >"$(dirname "$proton")/files/bin/wineserver"
chmod +x "$(dirname "$proton")"/files/bin/*

export G29_SYSFS_ROOT="$test_root/sys" NFSU2_PROBE_LAUNCHER= XDG_STATE_HOME="$test_root/state"
export STEAM_COMPAT_DATA_PATH="$test_root/compat"
state() {
  echo "$(grep -o 'Support = [0-9]' "$scripts/NFSUnderground2.WidescreenFix.ini") c=$(<"$wheel/combine_pedals") $(cd "$scripts" && ls -- *.asi* | tr '\n' ' ')"
}

during=$("$wrapper" bash -c "$(declare -f state); scripts='$scripts' wheel='$wheel' state; exit 5" "$proton" "$game/SPEED2.exe") \
  && fail "game exit status lost" || [[ $? == 5 ]] || fail "game exit status lost"
[[ $during == "Support = 0 c=1 ffb.asi modupdater.asi.off NFSU2SplitScreen.asi.wrapper-off " ]] || fail "wheel mode: $during"
[[ $(state) == "Support = 2 c=0 ffb.asi modupdater.asi.off NFSU2SplitScreen.asi " ]] || fail "wheel mode not restored: $(state)"
grep -q '^steer = {9E573EDA-7734-11D2-8D4A-23903FB6BDF7}' "$game/ffb.ini" || fail "wheel GUID not updated"
grep -q '^throttle = {9E573EDA-7734-11D2-8D4A-23903FB6BDF7}|Z|32639|983' "$game/ffb.ini" || fail "throttle line changed"
grep -q '^handbrake = {9E573ED2-7734-11D2-8D4A-23903FB6BDF7}|X|1966|63569' "$game/ffb.ini" || fail "handbrake GUID not updated"
grep -q '^seq_device = {9E573EDA-7734-11D2-8D4A-23903FB6BDF7} ; comment' "$game/ffb.ini" || fail "seq_device not updated"

before=$(<"$game/ffb.ini")
during=$(G29_SYSFS_ROOT="$test_root/none" "$wrapper" bash -c "$(declare -f state); scripts='$scripts' wheel='$wheel' state" "$proton" "$game/SPEED2.exe")
[[ $during == "Support = 2 c=0 ffb.asi.wrapper-off modupdater.asi.off NFSU2SplitScreen.asi " ]] || fail "pad mode: $during"
[[ $(state) == "Support = 2 c=0 ffb.asi modupdater.asi.off NFSU2SplitScreen.asi " ]] || fail "pad mode not restored: $(state)"
[[ $(<"$game/ffb.ini") == "$before" ]] || fail "pad mode touched ffb.ini"

# Wine 11 (GE-Proton 11) logs cached instance GUIDs in another format.
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
dev() { echo "00e4:trace:dinput:insert_cache_entry Created instance product: $1:$2, instance: {$3}, path L\"\"" >&2; }
dev 046d c24f 5869146f-ce80-11f1-8001-000044455354
dev 1209 4842 58691c58-ce80-11f1-8002-000044455354
exec sleep 30
EOF
"$wrapper" true "$proton" "$game/SPEED2.exe"
grep -q '^steer = {5869146F-CE80-11F1-8001-000044455354}' "$game/ffb.ini" || fail "Wine 11 wheel GUID not read"
grep -q '^handbrake = {58691C58-CE80-11F1-8002-000044455354}|X|1966|63569' "$game/ffb.ini" || fail "Wine 11 handbrake GUID not read"

mv "$scripts/ffb.asi" "$scripts/ffb.asi.wrapper-off"
G29_SYSFS_ROOT="$test_root/none" "$wrapper" true "$game/SPEED2.exe"
[[ -f $scripts/ffb.asi && ! -e $scripts/ffb.asi.wrapper-off ]] || fail "leftover plugin not recovered"

echo "nfsu2 wrapper tests passed"
