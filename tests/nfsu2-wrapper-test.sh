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
clutch = {9E573EDF-7734-11D2-8D4A-23903FB6BDF7}|Y|65535|983
seq_up = 5
clutch = off               ; off, required or delay
EOF
# Stand-in Wine: prints the dinput trace lines the probe parses.
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
[[ $1 == reg ]] && { echo "$*" >>"$WINE_REG_LOG"; exit 0; }
dev() { echo "0024:trace:dinput:hid_joystick_enum_device found device L\"\\\\\\\\?\\\\hid#vid_$1&pid_$2#x\", usage 0001:0004, product {x}, instance {$3}, name L\"x\"" >&2; }
dev 046d c24f 9e573eda-7734-11d2-8d4a-23903fb6bdf7
dev 1209 4842 9e573ed2-7734-11d2-8d4a-23903fb6bdf7
exec sleep 30
EOF
printf '#!/bin/sh\n' >"$(dirname "$proton")/files/bin/wineserver"
chmod +x "$(dirname "$proton")"/files/bin/*

export G29_SYSFS_ROOT="$test_root/sys" NFSU2_PROBE_LAUNCHER= XDG_STATE_HOME="$test_root/state"
export STEAM_COMPAT_DATA_PATH="$test_root/compat" WINE_REG_LOG="$test_root/wine-reg.log"
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
# Steam's virtual pad ignores the SDL list; it is disabled in DirectInput for
# the session and enabled again on exit.
[[ $(<"$WINE_REG_LOG") == 'reg add HKCU\Software\Wine\DirectInput\Joysticks /v Controller (XBOX 360 For Windows) /d disabled /f
reg delete HKCU\Software\Wine\DirectInput\Joysticks /v Controller (XBOX 360 For Windows) /f' ]] ||
  fail "Steam pad not disabled for the session: $(<"$WINE_REG_LOG")"
rm -f -- "$WINE_REG_LOG"

before=$(<"$game/ffb.ini")
during=$(G29_SYSFS_ROOT="$test_root/none" "$wrapper" bash -c "$(declare -f state); scripts='$scripts' wheel='$wheel' state" "$proton" "$game/SPEED2.exe")
[[ $during == "Support = 2 c=0 ffb.asi.wrapper-off modupdater.asi.off NFSU2SplitScreen.asi " ]] || fail "pad mode: $during"
[[ $(state) == "Support = 2 c=0 ffb.asi modupdater.asi.off NFSU2SplitScreen.asi " ]] || fail "pad mode not restored: $(state)"
[[ $(<"$game/ffb.ini") == "$before" ]] || fail "pad mode touched ffb.ini"
[[ ! -e $WINE_REG_LOG ]] || fail "pad mode touched the registry"

# Wine 11 (GE-Proton 11) logs cached instance GUIDs in another format.
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
[[ $1 == reg ]] && { echo "$*" >>"$WINE_REG_LOG"; exit 0; }
dev() { echo "00e4:trace:dinput:insert_cache_entry Created instance product: $1:$2, instance: {$3}, path L\"\"" >&2; }
dev 046d c24f 5869146f-ce80-11f1-8001-000044455354
dev 1209 4842 58691c58-ce80-11f1-8002-000044455354
exec sleep 30
EOF
"$wrapper" true "$proton" "$game/SPEED2.exe"
grep -q '^steer = {5869146F-CE80-11F1-8001-000044455354}' "$game/ffb.ini" || fail "Wine 11 wheel GUID not read"
grep -q '^handbrake = {58691C58-CE80-11F1-8002-000044455354}|X|1966|63569' "$game/ffb.ini" || fail "Wine 11 handbrake GUID not read"

# Wheel mode tells the handbrake bridge to skip the lever's button 1 (nitro in
# the game) while the game runs; pad mode leaves it alone.
mkdir -p "$test_root/run"
export HANDBRAKE_AXIS_ONLY_FLAG="$test_root/run/axis-only"
# The wrapper runs its arguments as the game command; bash -c gets the flag
# path as $0 and ignores the Proton and game paths after it.
"$wrapper" bash -c '[[ -e $0 ]]' "$HANDBRAKE_AXIS_ONLY_FLAG" "$proton" "$game/SPEED2.exe" ||
  fail "axis-only flag missing in wheel mode"
[[ ! -e $HANDBRAKE_AXIS_ONLY_FLAG ]] || fail "axis-only flag left after exit"
G29_SYSFS_ROOT="$test_root/none" "$wrapper" bash -c '[[ ! -e $0 ]]' "$HANDBRAKE_AXIS_ONLY_FLAG" "$game/SPEED2.exe" ||
  fail "axis-only flag set in pad mode"

# A G923 Xbox edition in PC mode also gets wheel mode, without combine_pedals.
# Its first launch saves the G29's tuned pedal lines as the G29 profile.
g923="$test_root/g923/bus/hid/devices/0003:046D:C26E.000C"
mkdir -p "$g923"
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
[[ $1 == reg ]] && { echo "$*" >>"$WINE_REG_LOG"; exit 0; }
dev() { echo "00e4:trace:dinput:insert_cache_entry Created instance product: $1:$2, instance: {$3}, path L\"\"" >&2; }
dev 046d c26e 7a000001-ce80-11f1-8001-000044455354
dev 1209 4842 58691c58-ce80-11f1-8002-000044455354
exec sleep 30
EOF
during=$(G29_SYSFS_ROOT="$test_root/g923" "$wrapper" bash -c "$(declare -f state); scripts='$scripts' wheel='$wheel' state" "$proton" "$game/SPEED2.exe")
[[ $during == "Support = 0 c=0 ffb.asi modupdater.asi.off NFSU2SplitScreen.asi.wrapper-off " ]] || fail "G923 wheel mode: $during"
grep -q '^steer = {7A000001-CE80-11F1-8001-000044455354}' "$game/ffb.ini" || fail "G923 GUID not written"
grep -qx 'throttle = {5869146F-CE80-11F1-8001-000044455354}|Z|32639|983' "$game/ffb-wheel.g29.ini" || fail "G29 pedals not saved"

# With its own profile the G923 gets its pedal lines; the G29 gets its back.
printf '%s\n' 'throttle = {0}|Y|65535|0' 'clutch = {0}|Rz|65535|0' 'clutch = required' 'seq_up = 9' >"$game/ffb-wheel.g923.ini"
G29_SYSFS_ROOT="$test_root/g923" "$wrapper" true "$proton" "$game/SPEED2.exe"
grep -qx 'throttle = {7A000001-CE80-11F1-8001-000044455354}|Y|65535|0' "$game/ffb.ini" || fail "G923 pedals not applied"
grep -qx 'clutch = {7A000001-CE80-11F1-8001-000044455354}|Rz|65535|0' "$game/ffb.ini" || fail "G923 clutch axis not applied"
grep -qx 'clutch = required' "$game/ffb.ini" || fail "G923 clutch mode not applied"
grep -qx 'seq_up = 9' "$game/ffb.ini" || fail "G923 paddle not applied"
grep -q '^handbrake = {58691C58-CE80-11F1-8002-000044455354}|X|1966|63569' "$game/ffb.ini" || fail "handbrake line changed"
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
[[ $1 == reg ]] && { echo "$*" >>"$WINE_REG_LOG"; exit 0; }
echo "00e4:trace:dinput:insert_cache_entry Created instance product: 046d:c24f, instance: {5869146f-ce80-11f1-8001-000044455354}, path L\"\"" >&2
exec sleep 30
EOF
"$wrapper" true "$proton" "$game/SPEED2.exe"
grep -qx 'throttle = {5869146F-CE80-11F1-8001-000044455354}|Z|32639|983' "$game/ffb.ini" || fail "G29 pedals not restored"
grep -qx 'clutch = {5869146F-CE80-11F1-8001-000044455354}|Y|65535|983' "$game/ffb.ini" || fail "G29 clutch axis not restored"
grep -qx 'clutch = off               ; off, required or delay' "$game/ffb.ini" || fail "G29 clutch mode not restored"
grep -qx 'seq_up = 5' "$game/ffb.ini" || fail "G29 paddle not restored"
grep -qx 'throttle = {7A000001-CE80-11F1-8001-000044455354}|Y|65535|0' "$game/ffb-wheel.g923.ini" && fail "G923 profile overwritten"
grep -qx 'throttle = {0}|Y|65535|0' "$game/ffb-wheel.g923.ini" || fail "G923 profile changed"

# With the bridge the G923 reaches the game without its clutch: the real wheel
# is hidden, ffb.ini names the bridge, and the bridge stops with the game.
bridge="$test_root/bin/nfsmw-wheel-bridge" devices="$test_root/input-devices"
mkdir -p "${bridge%/*}"
cat >"$bridge" <<EOF
#!/usr/bin/env bash
[[ \$1 == --separate-pedals ]] || exit 1
echo 'N: Name="Omarchy NFS Wheel"' >"$devices"
trap 'rm -f "$devices"; exit 0' TERM
while :; do sleep 0.1; done
EOF
chmod +x "$bridge"
cat >"$(dirname "$proton")/files/bin/wine" <<'EOF'
#!/usr/bin/env bash
[[ $1 == reg ]] && { echo "$*" >>"$WINE_REG_LOG"; exit 0; }
dev() { echo "00e4:trace:dinput:insert_cache_entry Created instance product: $1:$2, instance: {$3}, path L\"\"" >&2; }
[[ $SDL_GAMECONTROLLER_IGNORE_DEVICES == *0x046d/0xc26e* ]] || dev 046d c26e 7a000001-ce80-11f1-8001-000044455354
dev 1209 4843 7b000002-ce80-11f1-8001-000044455354
exec sleep 30
EOF
during=$(SDL_GAMECONTROLLER_IGNORE_DEVICES=0x28de/0x1205 G29_SYSFS_ROOT="$test_root/g923" NFSU2_WHEEL_BRIDGE="$bridge" \
  NFSU2_INPUT_DEVICES="$devices" "$wrapper" bash -c 'echo "$SDL_GAMECONTROLLER_IGNORE_DEVICES"' "$proton" "$game/SPEED2.exe")
[[ $during == 0x28de/0x1205,0x054c/0x0ce6,0x054c/0x0df2,0x046d/0xc26e ]] || fail "real G923 and pads not hidden: $during"
grep -q '^steer = {7B000002-CE80-11F1-8001-000044455354}' "$game/ffb.ini" || fail "bridge GUID not written"
[[ ! -e $devices ]] || fail "bridge left running"

mv "$scripts/ffb.asi" "$scripts/ffb.asi.wrapper-off"
G29_SYSFS_ROOT="$test_root/none" "$wrapper" true "$game/SPEED2.exe"
[[ -f $scripts/ffb.asi && ! -e $scripts/ffb.asi.wrapper-off ]] || fail "leftover plugin not recovered"

echo "nfsu2 wrapper tests passed"
