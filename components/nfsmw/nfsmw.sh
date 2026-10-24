#!/usr/bin/env bash
# NFS Most Wanted Remaster (DODI repack of the GAMETEST modded release) under
# Proton: install|check|dry-run|pinnacle|pinnacle-revert. install adds the
# non-Steam shortcut with the G923 wheel wrapper (Steam must be closed) and the
# prefix registry settings; pinnacle swaps the repack's ReShade for Pinnacle of
# View (backing it up first) and pinnacle-revert puts it back; check and
# dry-run change nothing.
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
# Pinnacle of View: the NFSU2 component's DXVK patch and layer manifest.
nfsu2_dir="$component_dir/../nfsu2"
downloads=${NFSMW_DOWNLOADS:-$HOME/Downloads/nfs-most-wanted}
pinnacle_dir=${NFSMW_PINNACLE_DIR:-$(find "$downloads" -maxdepth 1 -type d -name 'PinancleofView*' 2>/dev/null | sort | tail -1)}
vulkan_zip=${NFSMW_VULKAN_RT_ZIP:-$HOME/Downloads/nfsu2/vulkan-runtime-components.zip}
pinnacle_backup="$backup_root/nfsmw-pre-pinnacle"
# What Pinnacle replaces; the backup holds the repack's copies.
repack_files=(d3d9.dll d3d9.ini scripts reshade-shaders)
pinnacle_files=(reshade32.dll dlss5-feed.addon32 dlss5-feed.cfg PinancleofView-DFC.ini ReShade.ini ReShade.log
  dlss5-feed.log vulkan-1.dll ReShade32.json host64)
layers_key='Software\\Wow6432Node\\Khronos\\Vulkan\\ImplicitLayers'

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
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }
pinnacle_on() { [[ -f $game_dir/reshade32.dll ]]; }
# Z:\home\...\ReShade32.json, the path the Windows loader sees.
win_path() { local p=${1//\//\\}; printf 'Z:%s' "$p"; }
layer_line() { local p; p=$(win_path "$game_dir/ReShade32.json"); printf '"%s"=dword:00000000' "${p//\\/\\\\}"; }
layer_set() { reg_has "$1/system.reg" "$layers_key" "$(layer_line)"; }
dxvk_patched() { grep -aq 'winevulkaX\.dll' "$1" 2>/dev/null && ! grep -aq 'winevulkan\.dll' "$1"; }
proton_reg() {
  local pfx; pfx=$(prefix)
  STEAM_COMPAT_DATA_PATH="${pfx%/pfx}" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
    "$proton" run reg "$@" >/dev/null 2>&1
}
# Wine saves the registry files when its server exits.
wine_sync() {
  local server; server="$(dirname -- "$proton")/files/bin/wineserver"
  [[ -x $server ]] && WINEPREFIX="$(prefix)" "$server" -w
  return 0
}

dry_run() {
  say "Non-Steam shortcut \"$name\" -> $game_dir/speed.exe (appid $(appid)), $compat_tool"
  say "d3dcompiler_47.dll (32-bit) from $compiler, ReShade cache in .\\reshade-cache"
  say "Prefix $(prefix): dinput8 (ASI loader), d3d9 (ReShade), d3dcompiler_47 = native,builtin; winebus DisableHidraw"
  say "Install ${wheel_files[*]} to $bin_dir; launch option: $launch_options"
  say "pinnacle: Pinnacle of View from ${pinnacle_dir:-<not found in $downloads>}, repack files backed up to $pinnacle_backup,"
  say "  patched DXVK d3d9.dll, Khronos vulkan-1.dll from $vulkan_zip, ReShade32.json as an implicit Vulkan layer"
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
  # The repack points ReShade at the repacker's own temp folder. Under
  # Pinnacle of View there is no d3d9.ini.
  [[ -f $game_dir/d3d9.ini ]] && sed -i 's|^IntermediateCachePath=.*|IntermediateCachePath=.\\reshade-cache\r|' "$game_dir/d3d9.ini"
  say "d3dcompiler_47.dll installed for ReShade"
}

install_registry() {
  [[ -x $proton ]] || { warn "Proton not found: $proton (set NFSMW_PROTON)"; return 1; }
  local pfx dll
  pfx=$(prefix)
  mkdir -p -- "${pfx%/pfx}"
  for dll in "${dlls[@]}"; do
    dll_set "$pfx" "$dll" || proton_reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native,builtin /f
  done
  # Wine otherwise opens the G923 through hidraw, whose vendor-page
  # collections DirectInput skips: the game finds no controller.
  hidraw_off "$pfx" || proton_reg add 'HKLM\System\CurrentControlSet\Services\winebus' /v DisableHidraw /t REG_DWORD /d 1 /f
  wine_sync
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

pinnacle_files_install() {
  [[ -f $pinnacle_dir/reshade32.dll ]] || { warn "Pinnacle of View not found in $downloads (extract it there or set NFSMW_PINNACLE_DIR)"; return 1; }
  local first=0 f
  pinnacle_on || first=1
  if [[ ! -d $pinnacle_backup ]]; then
    mkdir -p -- "$pinnacle_backup" || return 1
    for f in "${repack_files[@]}"; do
      [[ -e $game_dir/$f ]] && { cp -a -- "$game_dir/$f" "$pinnacle_backup/" || return 1; }
    done
    say "Repack ReShade and scripts backed up to $pinnacle_backup"
  fi
  # The repack's d3d9.dll is ReShade; under Pinnacle it is DXVK.
  ((first)) && rm -rf -- "$game_dir/reshade-shaders" "$game_dir/d3d9.ini"
  cp -f -- "$pinnacle_dir"/{reshade32.dll,dlss5-feed.addon32} "$game_dir/" || return 1
  cp -a -- "$pinnacle_dir/reshade-shaders" "$pinnacle_dir/host64" "$game_dir/" || return 1
  cp -f -- "$pinnacle_dir"/scripts/*.asi "$game_dir/scripts/" || return 1
  if ((first)); then
    cp -f -- "$pinnacle_dir"/{PinancleofView-DFC.ini,ReShade.ini,dlss5-feed.cfg} "$game_dir/" || return 1
    # Pinnacle's WidescreenFix and HDReflections are newer and need their own
    # inis. Extra Options keeps the repack's gameplay settings.
    for f in "$pinnacle_dir"/scripts/*; do
      [[ ${f##*/} == *.asi || ${f##*/} == NFSMWExtraOptionsSettings.ini ]] || cp -f -- "$f" "$game_dir/scripts/" || return 1
    done
    # Keep the repack's Xbox prompts and settings.ini storage.
    sed -i 's/^\(ImproveGamepadSupport = \)[0-9]/\11/; s/^\(WriteSettingsToFile = \)[0-9]/\11/' \
      "$game_dir/scripts/NFSMostWanted.WidescreenFix.ini"
    # The pack's bloom streaks (stretch 10) wash the picture out; use the
    # bloom section tuned in NFSU2.
    python3 -I -c 'import sys
section = open(sys.argv[1]).read().split("\n")
section = [l for l in section if l]
lines = open(sys.argv[2], newline="").read().split("\r\n")
start = lines.index(section[0])
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[") or not lines[i]), len(lines))
lines[start:end] = section
open(sys.argv[2], "w", newline="").write("\r\n".join(lines))' \
      "$component_dir/pinnacle-bloom.ini" "$game_dir/PinancleofView-DFC.ini" || { warn "could not set the preset's bloom"; return 1; }
  fi
  # The pack ships the author's logs and crash dump.
  rm -f -- "$game_dir"/host64/*.log "$game_dir"/host64/*.dmp
  sed -i 's|^IntermediateCachePath=.*|IntermediateCachePath=.\\reshade-cache\r|; s/^EnableProxyLibrary=1/EnableProxyLibrary=0/' \
    "$game_dir/ReShade.ini"
  say "Pinnacle of View files installed$( ((first)) && printf ' (first install)')"
}

pinnacle_dxvk_install() {
  local tmp; tmp=$(mktemp) || return 1
  python3 -I "$nfsu2_dir/patch_dxvk.py" "$pinnacle_dir/d3d9.dll" "$tmp" >/dev/null || { rm -f -- "$tmp"; return 1; }
  same "$tmp" "$game_dir/d3d9.dll" || install -m644 -- "$tmp" "$game_dir/d3d9.dll" || { rm -f -- "$tmp"; return 1; }
  rm -f -- "$tmp"
  [[ -f $vulkan_zip ]] || { warn "Vulkan runtime not found: $vulkan_zip (see components/nfsu2/README.md; set NFSMW_VULKAN_RT_ZIP)"; return 1; }
  tmp=$(mktemp) || return 1
  unzip -p "$vulkan_zip" '*/x86/vulkan-1.dll' >"$tmp" && [[ -s $tmp ]] || { rm -f -- "$tmp"; warn "$vulkan_zip has no x86/vulkan-1.dll"; return 1; }
  same "$tmp" "$game_dir/vulkan-1.dll" || install -m644 -- "$tmp" "$game_dir/vulkan-1.dll" || { rm -f -- "$tmp"; return 1; }
  rm -f -- "$tmp"
  same "$nfsu2_dir/ReShade32.json" "$game_dir/ReShade32.json" || install -m644 -- "$nfsu2_dir/ReShade32.json" "$game_dir/" || return 1
  say "Patched DXVK d3d9.dll, Khronos vulkan-1.dll and the ReShade layer manifest installed"
}

pinnacle_registry_install() {
  [[ -x $proton ]] || { warn "Proton not found: $proton (set NFSMW_PROTON)"; return 1; }
  local pfx; pfx=$(prefix)
  [[ -d $pfx ]] || { warn "no Proton prefix: $pfx (run install and launch the game once)"; return 1; }
  dll_set "$pfx" vulkan-1 || proton_reg add 'HKCU\Software\Wine\DllOverrides' /v vulkan-1 /t REG_SZ /d native,builtin /f
  layer_set "$pfx" ||
    proton_reg add 'HKLM\Software\Khronos\Vulkan\ImplicitLayers' /v "$(win_path "$game_dir/ReShade32.json")" /t REG_DWORD /d 0 /f /reg:32
  wine_sync
  dll_set "$pfx" vulkan-1 && layer_set "$pfx" || { warn "registry entries did not save"; return 1; }
  say "Prefix loads vulkan-1.dll and the ReShade Vulkan layer"
}

pinnacle_install() {
  [[ -f $game_dir/speed.exe ]] || { warn "game not found: $game_dir/speed.exe (set NFSMW_GAME_DIR)"; return 1; }
  pgrep -x "$game_process" >/dev/null && { warn "the game is running; close it and rerun"; return 1; }
  pinnacle_files_install || return 1
  local failed=() step
  for step in dxvk registry; do
    "pinnacle_${step}_install" || failed+=("$step")
  done
  ((${#failed[@]} == 0)) || { warn "steps that need attention: ${failed[*]}"; return 1; }
}

pinnacle_revert() {
  pgrep -x "$game_process" >/dev/null && { warn "the game is running; close it and rerun"; return 1; }
  [[ -d $pinnacle_backup ]] || { warn "no backup in $pinnacle_backup; nothing to revert"; return 1; }
  local f
  for f in "${pinnacle_files[@]}" "${repack_files[@]}"; do rm -rf -- "${game_dir:?}/$f"; done
  for f in "${repack_files[@]}"; do
    [[ -e $pinnacle_backup/$f ]] && { cp -a -- "$pinnacle_backup/$f" "$game_dir/" || return 1; }
  done
  if [[ -x $proton && -d $(prefix) ]]; then
    proton_reg delete 'HKLM\Software\Khronos\Vulkan\ImplicitLayers' /v "$(win_path "$game_dir/ReShade32.json")" /f /reg:32
    proton_reg delete 'HKCU\Software\Wine\DllOverrides' /v vulkan-1 /f
    wine_sync
  fi
  say "Repack ReShade restored from $pinnacle_backup (kept for the next switch)"
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
  if pinnacle_on; then
    ok "ReShade: Pinnacle of View (pinnacle-revert restores the repack's)"
    dxvk_patched "$game_dir/d3d9.dll" && ok "d3d9.dll is DXVK patched to load vulkan-1.dll" \
      || fail "d3d9.dll is not the patched DXVK"
    [[ -f $game_dir/vulkan-1.dll ]] && ok "Khronos vulkan-1.dll installed" || fail "vulkan-1.dll missing"
    same "$nfsu2_dir/ReShade32.json" "$game_dir/ReShade32.json" && ok "ReShade layer manifest installed" \
      || fail "layer manifest missing: $game_dir/ReShade32.json"
    dll_set "$pfx" vulkan-1 && ok "prefix loads native vulkan-1" || fail "prefix lacks vulkan-1=native,builtin"
    layer_set "$pfx" && ok "ReShade Vulkan layer registered" || fail "ReShade32.json is not a registered implicit layer"
  else
    ok "ReShade: the repack's (pinnacle installs Pinnacle of View)"
  fi
  return "$failures"
}

case $action in
  install) install_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  pinnacle) pinnacle_install ;;
  pinnacle-revert) pinnacle_revert ;;
  *) printf 'ERROR nfsmw: unknown action %s (install|check|dry-run|pinnacle|pinnacle-revert)\n' "$action" >&2; exit 2 ;;
esac
