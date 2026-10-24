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
[[ $1 == run && $2 == reg && $3 == add ]] || exit 1
pfx="$STEAM_COMPAT_DATA_PATH/pfx"; mkdir -p "$pfx"
case $4 in
  HKCU*) printf '[Software\\\\Wine\\\\DllOverrides] 2\n"%s"="%s"\n\n' "$6" "${10}" >>"$pfx/user.reg" ;;
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
echo "nfsmw tests passed"
