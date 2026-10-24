#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/nfsmw/nfsmw.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export NFSMW_STEAM_ROOT="$test_root/steam"
export NFSMW_GAME_DIR="$test_root/games/Need For Speed Most Wanted Remaster Edition"
export NFSMW_PROTON="$NFSMW_STEAM_ROOT/compatibilitytools.d/proton/proton"
export NFSMW_BACKUP_DIR="$test_root/backups"
export NFSMW_D3DCOMPILER="$test_root/d3dcompiler_47_32.dll"
export NFSMW_PROCESS=no-such-proc
export NFSMW_STEAM_PROCESS=no-such-proc
export NFSMW_BIN_DIR="$test_root/bin"
g=$NFSMW_GAME_DIR

mkdir -p "$g/scripts" "$NFSMW_STEAM_ROOT/userdata/1/config" "$NFSMW_STEAM_ROOT/config" "$(dirname "$NFSMW_PROTON")"
for f in speed.exe dinput8.dll d3d9.dll scripts/NFSMWExtraOptions.asi scripts/NFSMostWanted.WidescreenFix.asi \
  scripts/NFSMWUnlimiter.asi; do touch "$g/$f"; done
printf '[GENERAL]\r\nIntermediateCachePath=C:\\Users\\IONUT GAMING\\AppData\\Local\\Temp\r\nPerformanceMode=0\r\n' >"$g/d3d9.ini"
echo compiler >"$NFSMW_D3DCOMPILER"
export NFSMW_D3DCOMPILER_SHA=$(sha256sum <"$NFSMW_D3DCOMPILER" | cut -d' ' -f1)
python3 -I -c 'import sys, vdf; vdf.binary_dump({"shortcuts": {"0": {"appid": 1, "appname": "Other", "exe": "\"/x\""}}}, open(sys.argv[1], "wb"))' \
  "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf"
cat >"$NFSMW_STEAM_ROOT/config/config.vdf" <<'EOF'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
				}
			}
		}
	}
}
EOF

# Fake Proton: "run reg add KEY /v NAME /t TYPE /d DATA /f" appends to the
# registry file, the way Wine stores the key and value.
cat >"$NFSMW_PROTON" <<'EOF'
#!/usr/bin/env bash
[[ $1 == run && $2 == reg ]] || exit 1
pfx="$STEAM_COMPAT_DATA_PATH/pfx"; mkdir -p "$pfx"
reg_name() { local n=${1//\\/\\\\}; printf '"%s"' "$n"; }
if [[ $3 == delete ]]; then
  for f in "$pfx"/{user,system}.reg; do
    [[ -f $f ]] && grep -vF "$(reg_name "$6")=" "$f" >"$f.tmp"; mv -f "$f.tmp" "$f"
  done
  exit 0
fi
[[ $3 == add ]] || exit 1
case $4 in
  HKCU*) printf '[Software\\\\Wine\\\\DllOverrides] 2\n"%s"="%s"\n\n' "$6" "${10}" >>"$pfx/user.reg" ;;
  HKLM*Khronos*) printf '[Software\\\\Wow6432Node\\\\Khronos\\\\Vulkan\\\\ImplicitLayers] 2\n%s=dword:%08x\n\n' "$(reg_name "$6")" "${10}" >>"$pfx/system.reg" ;;
  HKLM*) printf '[System\\\\ControlSet001\\\\Services\\\\winebus] 2\n"%s"=dword:%08x\n\n' "$6" "${10}" >>"$pfx/system.reg" ;;
esac
EOF
chmod +x "$NFSMW_PROTON"

"$script" check >/dev/null && fail "check passed before install"
"$script" install >"$test_root/install.log" || { cat "$test_root/install.log"; fail "install failed"; }
"$script" check >"$test_root/check.log" || { cat "$test_root/check.log"; fail "check failed after install"; }

appid=$(python3 -I -c 'import sys, zlib; print((zlib.crc32(sys.argv[1].encode()) & 0xffffffff) | 0x80000000)' \
  "\"$g/speed.exe\"Need for Speed: Most Wanted")
grep -q "^OK   nfsmw: Steam shortcut present ($appid)" "$test_root/check.log" || fail "shortcut appid is not Steam's"
python3 -I -c 'import sys, vdf
d = vdf.binary_load(open(sys.argv[1], "rb"))["shortcuts"]
assert len(d) == 2 and d["0"]["appname"] == "Other", d
e = d["1"]
assert e["appid"] & 0xffffffff == int(sys.argv[2]) and e["StartDir"] == sys.argv[3] + "/", e' \
  "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf" "$appid" "$g" || fail "shortcut entry wrong"
grep -A2 "\"$appid\"" "$NFSMW_STEAM_ROOT/config/config.vdf" | grep -q '"UMU-Proton-10.0-4-proton"' || fail "compat tool not mapped"
[[ $(cat "$g/d3dcompiler_47.dll") == compiler ]] || fail "compiler not copied"
grep -q $'^IntermediateCachePath=.\\\\reshade-cache\r$' "$g/d3d9.ini" || fail "ReShade cache path not fixed"
grep -q $'^PerformanceMode=0\r$' "$g/d3d9.ini" || fail "other ini lines changed"
for dll in dinput8 d3d9 d3dcompiler_47; do
  grep -Fxq "\"$dll\"=\"native,builtin\"" "$NFSMW_STEAM_ROOT/steamapps/compatdata/$appid/pfx/user.reg" || fail "$dll override missing"
done
grep -Fxq '"DisableHidraw"=dword:00000001' "$NFSMW_STEAM_ROOT/steamapps/compatdata/$appid/pfx/system.reg" || fail "DisableHidraw missing"
for f in nfsmw-wheel-wrapper nfsmw-wheel-bridge; do
  [[ -x $NFSMW_BIN_DIR/$f ]] || fail "$f not installed"
done
python3 -I -c 'import sys, vdf
e = vdf.binary_load(open(sys.argv[1], "rb"))["shortcuts"]["1"]
assert e["LaunchOptions"] == sys.argv[2] + "/nfsmw-wheel-wrapper %command%", e' \
  "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf" "$NFSMW_BIN_DIR" || fail "launch option not set"

# A rerun adds no second shortcut, mapping or registry entry.
user_reg="$NFSMW_STEAM_ROOT/steamapps/compatdata/$appid/pfx/user.reg"
system_reg="${user_reg%/*}/system.reg"
cp "$system_reg" "$test_root/system.before"
cp "$user_reg" "$test_root/user.before"; cp "$NFSMW_STEAM_ROOT/config/config.vdf" "$test_root/config.before"
cp "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf" "$test_root/shortcuts.before"
"$script" install >/dev/null || fail "second install failed"
cmp -s "$user_reg" "$test_root/user.before" || fail "rerun rewrote the registry"
cmp -s "$system_reg" "$test_root/system.before" || fail "rerun rewrote system.reg"
cmp -s "$NFSMW_STEAM_ROOT/config/config.vdf" "$test_root/config.before" || fail "rerun rewrote config.vdf"
cmp -s "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf" "$test_root/shortcuts.before" || fail "rerun rewrote shortcuts.vdf"

# An existing shortcut gets the launch option, unless the user set their own.
set_options() {
  python3 -I -c 'import sys, vdf
d = vdf.binary_load(open(sys.argv[1], "rb")); d["shortcuts"]["1"]["LaunchOptions"] = sys.argv[2]
vdf.binary_dump(d, open(sys.argv[1], "wb"))' "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf" "$1"
}
options() { python3 -I -c 'import sys, vdf; print(vdf.binary_load(open(sys.argv[1], "rb"))["shortcuts"]["1"]["LaunchOptions"])' \
  "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf"; }
set_options ""
"$script" install >/dev/null || fail "install over an empty launch option failed"
[[ $(options) == "$NFSMW_BIN_DIR/nfsmw-wheel-wrapper %command%" ]] || fail "empty launch option not filled: $(options)"
set_options "gamemoderun %command%"
"$script" install >/dev/null 2>&1 || fail "install with custom launch options failed"
[[ $(options) == "gamemoderun %command%" ]] || fail "custom launch option replaced"
"$script" check >"$test_root/check.custom" && fail "check passed with a custom launch option"
grep -q "^FAIL nfsmw: shortcut launch option" "$test_root/check.custom" || fail "check missed the custom launch option"
set_options "$NFSMW_BIN_DIR/nfsmw-wheel-wrapper %command%"

# Steam running blocks the shortcut step but not the others.
NFSMW_STEAM_PROCESS=bash "$script" install >/dev/null 2>"$test_root/err" && fail "install passed with Steam running"
grep -q 'steps that need attention: shortcut$' "$test_root/err" || fail "wrong steps failed with Steam running"

# A moved game keeps its shortcut and appid, so the prefix stays.
moved="$test_root/moved/Need For Speed Most Wanted Remaster Edition"
mkdir -p "${moved%/*}" && cp -a "$g" "$moved"
NFSMW_GAME_DIR=$moved "$script" install >/dev/null || fail "install after a move failed"
python3 -I -c 'import sys, vdf
d = vdf.binary_load(open(sys.argv[1], "rb"))["shortcuts"]
assert len(d) == 2, d
e = d["1"]
assert e["appid"] & 0xffffffff == int(sys.argv[2]) and e["exe"] == "\"%s/speed.exe\"" % sys.argv[3] \
  and e["StartDir"] == sys.argv[3] + "/", e' \
  "$NFSMW_STEAM_ROOT/userdata/1/config/shortcuts.vdf" "$appid" "$moved" || fail "moved shortcut entry wrong"
NFSMW_GAME_DIR=$moved "$script" check >"$test_root/check.moved" || { cat "$test_root/check.moved"; fail "check failed after a move"; }
grep -q "^OK   nfsmw: Steam shortcut present ($appid)" "$test_root/check.moved" || fail "move changed the appid"
"$script" install >/dev/null || fail "moving back failed"
rm -rf -- "$test_root/moved"
# pinnacle swaps in Pinnacle of View's DXVK + Vulkan-layer ReShade and keeps
# the repack's files for pinnacle-revert.
pin="$test_root/downloads/PinancleofView DFC 328"
mkdir -p "$pin/host64" "$pin/reshade-shaders/Shaders" "$pin/scripts" "$test_root/rt/VulkanRT/x86"
printf 'dxvk winevulkan.dll\0 and winevulkan.dll\0' >"$pin/d3d9.dll"
printf 'Techniques=x\r\n\r\n[lumenite_AnamorphicBloom.fx]\r\nBLOOM_INTENSITY=1.000000\r\nSTREAK_STRETCH=10.000000\r\n\r\n[qUINT_lightroom.fx]\r\nLIGHTROOM_GLOBAL_BLACK_LEVEL=8.000000\r\n' \
  >"$pin/PinancleofView-DFC.ini"
for f in reshade32.dll dlss5-feed.addon32 dlss5-feed.cfg host64/dlss5-feed-host.log \
  host64/dlss5-feed-host-crash.dmp host64/dlss5-feed-host64.exe reshade-shaders/Shaders/lumenite.fx \
  scripts/NFSMWHDReflections.asi scripts/NFSMWFEShadows.ini; do echo "pinnacle $f" >"$pin/$f"; done
printf '[GENERAL]\r\nIntermediateCachePath=C:\\Users\\Dg_pr\\Temp\r\n[PROXY]\r\nEnableProxyLibrary=0\r\n' >"$pin/ReShade.ini"
printf 'ImproveGamepadSupport = 0      ; x\r\nWriteSettingsToFile = 0     ; y\r\n' >"$pin/scripts/NFSMostWanted.WidescreenFix.ini"
echo 'EnableVisualTreatmentOverride = 0 // pinnacle' >"$pin/scripts/NFSMWExtraOptionsSettings.ini"
echo 'EnableVisualTreatmentOverride = 1 // repack' >"$g/scripts/NFSMWExtraOptionsSettings.ini"
mkdir -p "$g/reshade-shaders" && echo 'repack shader' >"$g/reshade-shaders/x.fx"
echo loader >"$test_root/rt/VulkanRT/x86/vulkan-1.dll"
(cd "$test_root/rt" && zip -qr ../vulkan-rt.zip VulkanRT)
export NFSMW_PINNACLE_DIR=$pin NFSMW_VULKAN_RT_ZIP="$test_root/vulkan-rt.zip"
cp -a "$g" "$test_root/repack"
"$script" pinnacle >"$test_root/pin.log" || { cat "$test_root/pin.log"; fail "pinnacle failed"; }
"$script" check >"$test_root/check.pin" || { cat "$test_root/check.pin"; fail "check failed under Pinnacle"; }
grep -q '^OK   nfsmw: ReShade layer manifest installed' "$test_root/check.pin" || fail "check skipped the Pinnacle checks"
grep -aq winevulkaX.dll "$g/d3d9.dll" && ! grep -aq winevulkan.dll "$g/d3d9.dll" || fail "DXVK not patched"
[[ $(cat "$g/vulkan-1.dll") == loader && ! -e $g/d3d9.ini && ! -e $g/reshade-shaders/x.fx ]] || fail "repack ReShade left in place"
[[ -f $g/reshade-shaders/Shaders/lumenite.fx && -f $g/scripts/NFSMWFEShadows.ini && -f $g/scripts/NFSMWUnlimiter.asi ]] \
  || fail "Pinnacle files or repack scripts missing"
[[ ! -e $g/host64/dlss5-feed-host.log && ! -e $g/host64/dlss5-feed-host-crash.dmp ]] || fail "author's logs copied"
grep -q $'^IntermediateCachePath=.\\\\reshade-cache\r$' "$g/ReShade.ini" || fail "Pinnacle cache path not fixed"
grep -q '^ImproveGamepadSupport = 1 ' "$g/scripts/NFSMostWanted.WidescreenFix.ini" \
  && grep -q '^WriteSettingsToFile = 1 ' "$g/scripts/NFSMostWanted.WidescreenFix.ini" || fail "WidescreenFix settings not kept"
grep -q '^EnableVisualTreatmentOverride = 1 // repack' "$g/scripts/NFSMWExtraOptionsSettings.ini" || fail "Extra Options ini not kept"
python3 -I -c 'import sys
want = "\r\n".join(l for l in open(sys.argv[1]).read().split("\n") if l)
got = open(sys.argv[2], newline="").read()
assert want + "\r\n\r\n[qUINT_lightroom.fx]\r\nLIGHTROOM_GLOBAL_BLACK_LEVEL=8.000000\r\n" in got and got.startswith("Techniques=x\r\n\r\n["), got' \
  "$repo_dir/components/nfsmw/pinnacle-bloom.ini" "$g/PinancleofView-DFC.ini" || fail "bloom section not applied"
grep -Fxq '"vulkan-1"="native,builtin"' "$user_reg" || fail "vulkan-1 override missing"
grep -q 'ReShade32.json"=dword:00000000' "$system_reg" || fail "layer not registered"
cp "$system_reg" "$test_root/system.pin"
echo tweaked >>"$g/PinancleofView-DFC.ini"
"$script" pinnacle >/dev/null || fail "second pinnacle failed"
cmp -s "$system_reg" "$test_root/system.pin" || fail "rerun rewrote system.reg"
grep -q tweaked "$g/PinancleofView-DFC.ini" || fail "rerun replaced the Pinnacle preset"
"$script" pinnacle-revert >/dev/null || fail "pinnacle-revert failed"
diff -r "$test_root/repack" "$g" >/dev/null || { diff -r "$test_root/repack" "$g"; fail "revert did not restore the repack files"; }
grep -q 'ReShade32.json' "$system_reg" && fail "layer still registered"
grep -q '"vulkan-1"' "$user_reg" && fail "vulkan-1 override left"
"$script" check >/dev/null || fail "check failed after revert"
echo "nfsmw tests passed"
