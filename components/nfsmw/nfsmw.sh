#!/usr/bin/env bash
# NFS Most Wanted Remaster (DODI repack of the GAMETEST modded release) under
# Proton: install|check|dry-run. install adds the non-Steam shortcut with the
# G923 wheel wrapper (Steam must be closed) and the prefix registry settings;
# check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
steam_root=${NFSMW_STEAM_ROOT:-$HOME/.local/share/Steam}
game_dir=${NFSMW_GAME_DIR:-$HOME/Games/Need For Speed Most Wanted Remaster Edition}
name=${NFSMW_NAME:-Need for Speed: Most Wanted}
compat_tool=${NFSMW_COMPAT_TOOL:-UMU-Proton-10.0-4-proton}
proton=${NFSMW_PROTON:-$steam_root/compatibilitytools.d/UMU-Proton-10.0-4/proton}
backup_root=${NFSMW_BACKUP_DIR:-$HOME/.local/state/omarchy-gaming-setup/backups}
game_process=${NFSMW_PROCESS:-speed.exe}
steam_process=${NFSMW_STEAM_PROCESS:-steam}
# Microsoft's 32-bit compiler, as winetricks d3dcompiler_47 fetches it.
compiler=${NFSMW_D3DCOMPILER:-$HOME/.cache/winetricks/d3dcompiler_47/d3dcompiler_47_32.dll}
compiler_sha=${NFSMW_D3DCOMPILER_SHA:-2ad0d4987fc4624566b190e747c9d95038443956ed816abfd1e2d389b5ec0851}
bin_dir=${NFSMW_BIN_DIR:-$HOME/.local/bin}
wheel_files=(nfsmw-wheel-wrapper nfsmw-wheel-bridge)
launch_options="$bin_dir/nfsmw-wheel-wrapper %command%"
dlls=(dinput8 d3d9 d3dcompiler_47)
overrides_key='Software\\Wine\\DllOverrides'
# reg add writes through CurrentControlSet; system.reg stores ControlSet001.
winebus_key='System\\ControlSet001\\Services\\winebus'
hidraw_line='"DisableHidraw"=dword:00000001'

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN nfsmw: %s\n' "$*" >&2; }
shortcuts_file() { find "$steam_root/userdata" -mindepth 3 -maxdepth 3 -path '*/config/shortcuts.vdf' 2>/dev/null | head -1; }
steam_args() {
  printf '%s\0' --shortcuts "$(shortcuts_file)" --config "$steam_root/config/config.vdf" \
    --exe "$game_dir/speed.exe" --name "$name" --compat-tool "$compat_tool" --backup-dir "$backup_root" \
    --launch-options "$launch_options"
}
appid() { steam_args | xargs -0 python3 -I "$component_dir/configure_steam.py" --print-appid; }
prefix() { printf '%s/steamapps/compatdata/%s/pfx' "$steam_root" "$(appid)"; }
# reg_has FILE KEY LINE: LINE is inside [KEY].
reg_has() {
  REG_KEY="[$2]" REG_LINE="$3" awk '
    BEGIN { key = ENVIRON["REG_KEY"]; line = ENVIRON["REG_LINE"] }
    index($0, key) == 1 { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && $0 == line { found = 1 }
    END { exit !found }' "$1" 2>/dev/null
}
dll_set() { reg_has "$1/user.reg" "$overrides_key" "\"$2\"=\"native,builtin\""; }
hidraw_off() { reg_has "$1/system.reg" "$winebus_key" "$hidraw_line"; }

dry_run() {
  say "Non-Steam shortcut \"$name\" -> $game_dir/speed.exe (appid $(appid)), $compat_tool"
  say "d3dcompiler_47.dll (32-bit) from $compiler, ReShade cache in .\\reshade-cache"
  say "Prefix $(prefix): dinput8 (ASI loader), d3d9 (ReShade), d3dcompiler_47 = native,builtin; winebus DisableHidraw"
  say "Install ${wheel_files[*]} to $bin_dir; launch option: $launch_options"
}

install_shortcut() {
  pgrep -x "$steam_process" >/dev/null && { warn "Steam is running; exit it and rerun"; return 1; }
  [[ -n $(shortcuts_file) ]] || { warn "no userdata/*/config/shortcuts.vdf under $steam_root"; return 1; }
  steam_args | xargs -0 python3 -I "$component_dir/configure_steam.py"
}

install_compiler() {
  [[ -f $compiler ]] || { warn "missing $compiler (run: winetricks --force d3dcompiler_47 in any prefix, or set NFSMW_D3DCOMPILER)"; return 1; }
  [[ $(sha256sum <"$compiler") == "$compiler_sha  -" ]] || { warn "$compiler is not the expected d3dcompiler_47_32.dll"; return 1; }
  install -m644 -- "$compiler" "$game_dir/d3dcompiler_47.dll" || return 1
  # The repack points ReShade at the repacker's own temp folder.
  sed -i 's|^IntermediateCachePath=.*|IntermediateCachePath=.\\reshade-cache\r|' "$game_dir/d3d9.ini"
  say "d3dcompiler_47.dll installed for ReShade"
}

install_registry() {
  [[ -x $proton ]] || { warn "Proton not found: $proton (set NFSMW_PROTON)"; return 1; }
  local compat pfx dll
  pfx=$(prefix); compat=${pfx%/pfx}
  mkdir -p -- "$compat"
  for dll in "${dlls[@]}"; do
    dll_set "$pfx" "$dll" && continue
    STEAM_COMPAT_DATA_PATH="$compat" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
      "$proton" run reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native,builtin /f >/dev/null 2>&1
  done
  # Wine otherwise opens the G923 through hidraw, whose vendor-page
  # collections DirectInput skips: the game finds no controller.
  hidraw_off "$pfx" || STEAM_COMPAT_DATA_PATH="$compat" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
    "$proton" run reg add 'HKLM\System\CurrentControlSet\Services\winebus' /v DisableHidraw /t REG_DWORD /d 1 /f >/dev/null 2>&1
  # Wine saves the registry files when its server exits.
  local server; server="$(dirname -- "$proton")/files/bin/wineserver"
  [[ -x $server ]] && WINEPREFIX="$pfx" "$server" -w
  for dll in "${dlls[@]}"; do
    dll_set "$pfx" "$dll" || { warn "$dll override did not save"; return 1; }
  done
  hidraw_off "$pfx" || { warn "DisableHidraw did not save"; return 1; }
  say "Prefix overrides set"
}

install_wheel() {
  mkdir -p -- "$bin_dir" || return 1
  local f
  for f in "${wheel_files[@]}"; do
    install -m755 -- "$component_dir/$f" "$bin_dir/$f" || return 1
  done
  say "Wheel wrapper and bridge installed to $bin_dir"
}

install_component() {
  [[ -f $game_dir/speed.exe ]] || { warn "game not found: $game_dir/speed.exe (set NFSMW_GAME_DIR)"; return 1; }
  pgrep -x "$game_process" >/dev/null && { warn "the game is running; close it and rerun"; return 1; }
  local failed=() step
  for step in wheel shortcut compiler registry; do
    "install_$step" || failed+=("$step")
  done
  ((${#failed[@]} == 0)) || { warn "steps that need attention: ${failed[*]}"; return 1; }
}

check_component() {
  local failures=0 pfx dll f
  ok() { printf 'OK   nfsmw: %s\n' "$*"; }
  fail() { printf 'FAIL nfsmw: %s\n' "$*"; failures=$((failures + 1)); }

  if [[ ! -f $game_dir/speed.exe ]]; then fail "game not found: $game_dir"; return "$failures"; fi
  for f in dinput8.dll d3d9.dll scripts/NFSMWExtraOptions.asi scripts/NFSMostWanted.WidescreenFix.asi scripts/NFSMWUnlimiter.asi; do
    [[ -f $game_dir/$f ]] || fail "$f missing"
  done
  ((failures == 0)) && ok "ASI loader, ReShade and the script mods are in place"
  [[ $(sha256sum 2>/dev/null <"$game_dir/d3dcompiler_47.dll") == "$compiler_sha  -" ]] && ok "Microsoft d3dcompiler_47 for ReShade" \
    || fail "d3dcompiler_47.dll missing: ReShade effects fail to compile with Wine's"
  python3 -I -c 'import sys, vdf
d = vdf.binary_load(open(sys.argv[1], "rb"))
sys.exit(not any(e.get("exe") == sys.argv[2] for e in d["shortcuts"].values()))' \
    "$(shortcuts_file)" "\"$game_dir/speed.exe\"" 2>/dev/null && ok "Steam shortcut present ($(appid))" \
    || fail "no Steam shortcut for speed.exe"
  python3 -I -c 'import sys, vdf
d = vdf.binary_load(open(sys.argv[1], "rb"))
sys.exit(not any(e.get("exe") == sys.argv[2] and e.get("LaunchOptions") == sys.argv[3] for e in d["shortcuts"].values()))' \
    "$(shortcuts_file)" "\"$game_dir/speed.exe\"" "$launch_options" 2>/dev/null && ok "launch option runs the wheel wrapper" \
    || fail "shortcut launch option is not: $launch_options"
  for f in "${wheel_files[@]}"; do
    cmp -s -- "$component_dir/$f" "$bin_dir/$f" || fail "$bin_dir/$f missing or out of date"
  done
  grep -q "\"$(appid)\"" "$steam_root/config/config.vdf" 2>/dev/null && ok "compatibility tool mapped" \
    || fail "no CompatToolMapping for $(appid)"
  pfx=$(prefix)
  for dll in "${dlls[@]}"; do
    dll_set "$pfx" "$dll" && ok "prefix loads native $dll" || fail "prefix lacks $dll=native,builtin"
  done
  hidraw_off "$pfx" && ok "prefix reads wheels through SDL (DisableHidraw)" \
    || fail "prefix lacks winebus DisableHidraw: the game finds no G923"
  return "$failures"
}

case $action in
  install) install_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) printf 'ERROR nfsmw: unknown action %s (install|check|dry-run)\n' "$action" >&2; exit 2 ;;
esac
