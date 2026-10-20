#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/nfsu2/nfsu2.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export NFSU2_STEAM_ROOT="$test_root/steam"
export NFSU2_GAME_DIR="$test_root/games/Need for Speed - Underground 2"
export NFSU2_COMPAT_DIR="$NFSU2_STEAM_ROOT/steamapps/compatdata/1"
export NFSU2_PROTON="$NFSU2_STEAM_ROOT/compatibilitytools.d/proton/proton"
export NFSU2_DOWNLOADS="$test_root/downloads"
prefix="$NFSU2_COMPAT_DIR/pfx"
pack="$NFSU2_DOWNLOADS/PinancleofView DFC 111"

mkdir -p "$NFSU2_GAME_DIR/scripts" "$prefix" "$(dirname "$NFSU2_PROTON")" \
  "$pack/scripts" "$pack/reshade-shaders/Shaders" "$pack/host64"
touch "$NFSU2_GAME_DIR/SPEED2.exe" "$NFSU2_GAME_DIR/scripts/NFSU2ExtraOptions.asi"
printf 'ImproveGamepadSupport = 2 ; repack\n' >"$NFSU2_GAME_DIR/scripts/NFSUnderground2.WidescreenFix.ini"
printf 'WINEFOO' >"$NFSU2_GAME_DIR/d3d9.dll"
printf '[Software\\\\Wine\\\\DllOverrides] 1\n"dinput8"="native,builtin"\n\n' >"$prefix/user.reg"
: >"$prefix/system.reg"

# The Pinnacle pack, with the author's logs and an enabled updater.
for f in reshade32.dll dinput8.dll dlss5-feed.addon32 PinancleofView-DFC.ini dlss5-feed.cfg; do echo "$f" >"$pack/$f"; done
printf 'DXVK\0winevulkan.dll\0vulkan-1.dll\0winevulkan.dll\0' >"$pack/d3d9.dll"
printf '[GENERAL]\r\nIntermediateCachePath=C:\\Users\\author\\Temp\r\n[PROXY]\r\nEnableProxyLibrary=1\r\n' >"$pack/ReShade.ini"
printf 'ImproveGamepadSupport = 4 ; pack\r\n' >"$pack/scripts/NFSUnderground2.WidescreenFix.ini"
touch "$pack/scripts/modupdater.asi" "$pack/scripts/NFSU2Unlimiter.asi" "$pack/host64/crash.dmp" "$pack/host64/host.log"
echo shader >"$pack/reshade-shaders/Shaders/A.fx"
(mkdir -p "$test_root/rt/VulkanRT-1/x86" && cd "$test_root/rt" && echo loader >VulkanRT-1/x86/vulkan-1.dll &&
  zip -qr "$NFSU2_DOWNLOADS/vulkan-runtime-components.zip" VulkanRT-1)

# Fake Proton: "run reg add KEY /v NAME /t TYPE /d DATA /f [/reg:32]" appends
# to the registry file the way Wine stores it.
cat >"$NFSU2_PROTON" <<'EOF'
#!/usr/bin/env bash
[[ $1 == run && $2 == reg ]] || exit 1
op=$3 key=$4 name=$6 type=$8 data=${10:-}
pfx="$STEAM_COMPAT_DATA_PATH/pfx"
esc() { printf '%s' "${1//\\/\\\\}"; }
[[ $op == add ]] || exit 0
case $key in
  HKCU\\*) file=$pfx/user.reg; key=${key#HKCU\\} ;;
  HKLM\\Software\\*) file=$pfx/system.reg; key="Software\\Wow6432Node\\${key#HKLM\\Software\\}" ;;
esac
case $type in REG_DWORD) value=$(printf 'dword:%08x' "$data") ;; *) value="\"$data\"" ;; esac
printf '[%s] 2\n"%s"=%s\n\n' "$(esc "$key")" "$(esc "$name")" "$value" >>"$file"
EOF
chmod +x "$NFSU2_PROTON"

"$script" check >/dev/null && fail "check passed before install"
"$script" install >"$test_root/install.log" || { cat "$test_root/install.log"; fail "install failed"; }
"$script" check >"$test_root/check.log" || { cat "$test_root/check.log"; fail "check failed after install"; }

g=$NFSU2_GAME_DIR
grep -aq 'winevulkaX.dll' "$g/d3d9.dll" && ! grep -aq 'winevulkan.dll' "$g/d3d9.dll" || fail "d3d9.dll not patched"
grep -aq 'vulkan-1.dll' "$g/d3d9.dll" || fail "patch touched vulkan-1.dll"
[[ $(cat "$g/vulkan-1.dll") == loader ]] || fail "vulkan-1.dll not taken from the runtime zip"
[[ -f $g/scripts/modupdater.asi.off && ! -f $g/scripts/modupdater.asi ]] || fail "updater still enabled"
[[ ! -e $g/host64/crash.dmp && ! -e $g/host64/host.log ]] || fail "author's logs copied"
grep -q '^ImproveGamepadSupport = 2 ; pack' "$g/scripts/NFSUnderground2.WidescreenFix.ini" || fail "pack ini not copied with PS prompts"
grep -q '^IntermediateCachePath=.\\reshade-cache' "$g/ReShade.ini" || fail "ReShade cache path not fixed"
grep -q '^EnableProxyLibrary=0' "$g/ReShade.ini" || fail "ReShade proxy not disabled"
grep -Fq '"Z:\\'  "$prefix/system.reg" && grep -Fq 'ReShade32.json"=dword:00000000' "$prefix/system.reg" || fail "layer not registered"
grep -Fxq '"vulkan-1"="native,builtin"' "$prefix/user.reg" || fail "vulkan-1 override missing"

# A rerun keeps in-game tweaks and adds no duplicate registry entries.
echo 'Effects=Mine.fx' >"$g/PinancleofView-DFC.ini"
cp "$prefix/user.reg" "$test_root/user.before"; cp "$prefix/system.reg" "$test_root/system.before"
"$script" install >/dev/null || fail "second install failed"
[[ $(cat "$g/PinancleofView-DFC.ini") == 'Effects=Mine.fx' ]] || fail "rerun overwrote the preset"
cmp -s "$prefix/user.reg" "$test_root/user.before" && cmp -s "$prefix/system.reg" "$test_root/system.before" ||
  fail "rerun rewrote the registry"

"$script" uninstall >/dev/null
[[ ! -e $g/d3d9.dll && ! -e $g/vulkan-1.dll && ! -e $g/ReShade32.json ]] || fail "uninstall left the chain"
echo "nfsu2 tests passed"
