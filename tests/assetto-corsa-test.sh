#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/assetto-corsa/assetto-corsa.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
# Fake protontricks records verbs in winetricks.log the way winetricks does.
printf '%s\n' '#!/usr/bin/env bash' 'shift 2; echo "$*" >>"$PROTONTRICKS_LOG"' \
  'printf "%s\n" "$@" >>"$AC_PREFIX/winetricks.log"' >"$fake_bin/protontricks"
chmod +x "$fake_bin/protontricks"

export PATH="$fake_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=
export PROTONTRICKS_LOG="$test_root/protontricks.log"
export AC_STEAM_ROOT="$test_root/steam"
export AC_GAME_DIR="$AC_STEAM_ROOT/steamapps/common/assettocorsa"
export AC_PREFIX="$AC_STEAM_ROOT/steamapps/compatdata/244210/pfx"
export AC_PROTON9="$AC_STEAM_ROOT/steamapps/common/Proton 9.0 (Beta)/proton"
export AC_BIN_DIR="$test_root/home/.local/bin"
export AC_HYPR_DIR="$test_root/home/.config/hypr"
export AC_CM_EXE="$test_root/downloads/Content Manager.exe"
export AC_FONTS_ZIP="$test_root/downloads/ac-fonts.zip"
export AC_BACKUP_DIR="$test_root/backups"
export AC_STEAM_PROCESS=omarchy-test-no-such-process
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$AC_GAME_DIR/content/fonts" "$AC_HYPR_DIR" "$(dirname "$AC_PROTON9")" \
  "$(dirname "$AC_CM_EXE")" "$AC_STEAM_ROOT/config" "$AC_STEAM_ROOT/userdata/1/config" "$AC_PREFIX"
echo original >"$AC_GAME_DIR/AssettoCorsa.exe"
echo content-manager >"$AC_CM_EXE"
printf '#!/bin/sh\n' >"$AC_PROTON9"; chmod +x "$AC_PROTON9"
echo 'require("hypr.monitors")' >"$AC_HYPR_DIR/hyprland.lua"
(cd "$test_root" && mkdir -p z/system && echo font >z/system/segoeui.ttf && cd z && zip -qr "$AC_FONTS_ZIP" system)
# The .NET installers leave the prefix on Windows 7.
printf '%s\n' vcrun2019 win7 dotnet48 >"$AC_PREFIX/winetricks.log"
cat >"$AC_STEAM_ROOT/userdata/1/config/localconfig.vdf" <<'EOF'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"244210"
					{
						"LaunchOptions"		"old %command%"
					}
				}
			}
		}
	}
}
EOF
cat >"$AC_STEAM_ROOT/config/config.vdf" <<'EOF'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"SDL_GamepadBind"		"line one,
line two,"
				"CompatToolMapping"
				{
					"0"
					{
						"name"		"proton_experimental"
						"config"		""
						"priority"		"75"
					}
				}
			}
		}
	}
}
EOF
cp "$AC_STEAM_ROOT/config/config.vdf" "$test_root/config.before"

output=$("$script" check) && fail "check passed before installation"
grep -q 'launch wrapper missing' <<<"$output" || fail "missing wrapper not reported"
grep -q 'prefix is not win10' <<<"$output" || fail "win7 prefix not reported"

"$script" dry-run >/dev/null
[[ ! -e $AC_BIN_DIR/ac-steam-wrapper ]] || fail "dry-run installed files"

# Steam running: everything else installs, Steam config is left alone.
AC_STEAM_PROCESS=bash "$script" install >/dev/null 2>&1 && fail "install passed while Steam was running"
grep -q 'old %command%' "$AC_STEAM_ROOT/userdata/1/config/localconfig.vdf" || fail "launch options changed with Steam running"

"$script" install >/dev/null || fail "install failed"
cmp -s "$repo_dir/components/assetto-corsa/ac-steam-wrapper" "$AC_BIN_DIR/ac-steam-wrapper" || fail "wrapper not installed"
grep -Fxq 'require("hypr.assettocorsa")' "$AC_HYPR_DIR/hyprland.lua" || fail "rule not required"
[[ $(<"$AC_GAME_DIR/AssettoCorsa.exe") == content-manager ]] || fail "Content Manager not installed"
[[ $(<"$AC_GAME_DIR/AssettoCorsa_original.exe") == original ]] || fail "original exe not kept"
[[ -f $AC_GAME_DIR/content/fonts/system/segoeui.ttf ]] || fail "fonts not installed"
grep -Fq "$AC_BIN_DIR/ac-steam-wrapper %command%" "$AC_STEAM_ROOT/userdata/1/config/localconfig.vdf" \
  || fail "launch options not set"
grep -q '"244210"' "$AC_STEAM_ROOT/config/config.vdf" || fail "compat tool entry not created"
grep -q 'line two,' "$AC_STEAM_ROOT/config/config.vdf" || fail "multi-line value damaged"
[[ $(diff "$test_root/config.before" "$AC_STEAM_ROOT/config/config.vdf" | grep -c '^>') == 6 ]] \
  || fail "config.vdf changed more than the new compat tool block"
grep -q 'd3dcompiler_43' "$PROTONTRICKS_LOG" || fail "missing verbs not installed"
grep -q 'vcrun2019' "$PROTONTRICKS_LOG" && fail "installed verb reinstalled"
grep -qx 'win10' "$PROTONTRICKS_LOG" || fail "prefix not switched to win10"
ls "$AC_BACKUP_DIR"/*/localconfig.vdf >/dev/null || fail "Steam config not backed up"

"$script" check >/dev/null || fail "check failed after install: $("$script" check)"

# Rerun is a no-op: no new protontricks calls, Content Manager not replaced.
calls=$(wc -l <"$PROTONTRICKS_LOG")
echo updated-content-manager >"$AC_GAME_DIR/AssettoCorsa.exe"
"$script" install >/dev/null || fail "rerun failed"
[[ $(wc -l <"$PROTONTRICKS_LOG") == "$calls" ]] || fail "rerun called protontricks"
[[ $(<"$AC_GAME_DIR/AssettoCorsa.exe") == updated-content-manager ]] || fail "rerun replaced Content Manager"

"$script" uninstall >/dev/null
[[ ! -e $AC_BIN_DIR/ac-steam-wrapper && ! -e $AC_HYPR_DIR/assettocorsa.lua ]] || fail "files not removed"
grep -q 'assettocorsa' "$AC_HYPR_DIR/hyprland.lua" && fail "require line not removed"
[[ $(<"$AC_GAME_DIR/AssettoCorsa.exe") == original ]] || fail "original exe not restored"

echo "assetto-corsa tests passed"
