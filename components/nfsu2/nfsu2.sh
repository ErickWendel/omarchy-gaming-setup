#!/usr/bin/env bash
# NFS Underground 2 (PC) + Pinnacle of View ReShade/DLSS under Proton:
# install|check|dry-run|uninstall. ReShade runs as a Vulkan layer on top of
# Pinnacle's DXVK, through the Khronos vulkan-1.dll (see README.md).
# install needs the game closed; check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
steam_root=${NFSU2_STEAM_ROOT:-$HOME/.local/share/Steam}
game_dir=${NFSU2_GAME_DIR:-$HOME/Games/Need for Speed - Underground 2}
# Non-Steam shortcut "SPEED2.exe".
appid=${NFSU2_APPID:-2674037821}
compat_dir=${NFSU2_COMPAT_DIR:-$steam_root/steamapps/compatdata/$appid}
prefix="$compat_dir/pfx"
proton=${NFSU2_PROTON:-$steam_root/compatibilitytools.d/UMU-Proton-10.0-4/proton}
downloads=${NFSU2_DOWNLOADS:-$HOME/Downloads/nfsu2}
pinnacle_dir=${NFSU2_PINNACLE_DIR:-$(find "$downloads" -maxdepth 1 -type d -name 'PinancleofView*' 2>/dev/null | sort | tail -1)}
vulkan_zip=${NFSU2_VULKAN_RT_ZIP:-$downloads/vulkan-runtime-components.zip}
game_process=${NFSU2_PROCESS:-SPEED2.exe}
layer_src="$component_dir/ReShade32.json"
layer_dst="$game_dir/ReShade32.json"
# Registry keys as Wine writes them in user.reg/system.reg.
overrides_key='Software\\Wine\\DllOverrides'
layers_key='Software\\Wow6432Node\\Khronos\\Vulkan\\ImplicitLayers'

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN nfsu2: %s\n' "$*" >&2; }
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }
game_running() { pgrep -x "$game_process" >/dev/null 2>&1; }
# Z:\home\...\ReShade32.json, the path the Windows loader sees.
win_path() { local p=${1//\//\\}; printf 'Z:%s' "$p"; }
# reg_has FILE KEY LINE: LINE is inside [KEY] of a Wine registry file.
reg_has() {
  # ENVIRON, not -v: awk would unescape the doubled backslashes.
  REG_KEY="[$2]" REG_LINE="$3" awk '
    BEGIN { key = ENVIRON["REG_KEY"]; line = ENVIRON["REG_LINE"] }
    index($0, key) == 1 { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && $0 == line { found = 1 }
    END { exit !found }' "$1" 2>/dev/null
}
layer_line() { local p; p=$(win_path "$layer_dst"); printf '"%s"=dword:00000000' "${p//\\/\\\\}"; }
proton_reg() {
  STEAM_COMPAT_DATA_PATH="$compat_dir" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
    "$proton" run reg "$@" >/dev/null 2>&1
  # Wine saves the registry files when its server exits.
  local server; server="$(dirname -- "$proton")/files/bin/wineserver"
  [[ -x $server ]] && WINEPREFIX="$prefix" "$server" -w
  return 0
}
dxvk_patched() { grep -aq 'winevulkaX\.dll' "$1" 2>/dev/null && ! grep -aq 'winevulkan\.dll' "$1"; }

dry_run() {
  say "Pinnacle of View files from: ${pinnacle_dir:-<not found in $downloads>}"
  say "  into $game_dir (configs only on first install), modupdater.asi disabled,"
  say "  ImproveGamepadSupport = 2, ReShade cache in .\\reshade-cache, ReShade proxy off"
  say "d3d9.dll: Pinnacle DXVK patched to load vulkan-1.dll (patch_dxvk.py)"
  say "vulkan-1.dll: Khronos x86 loader from $vulkan_zip"
  say "Vulkan layer manifest: $layer_dst"
  say "Prefix $prefix: dinput8 and vulkan-1 = native,builtin; ReShade32.json as an implicit layer"
}

install_files() {
  [[ -f $game_dir/SPEED2.exe ]] || { warn "game not found: $game_dir/SPEED2.exe (set NFSU2_GAME_DIR)"; return 1; }
  [[ -f $pinnacle_dir/reshade32.dll ]] || { warn "Pinnacle of View not found in $downloads (extract it there or set NFSU2_PINNACLE_DIR)"; return 1; }
  local first=0
  [[ -f $game_dir/reshade32.dll ]] || first=1
  cp -f -- "$pinnacle_dir"/{reshade32.dll,dinput8.dll,dlss5-feed.addon32} "$game_dir/" || return 1
  cp -a -- "$pinnacle_dir/reshade-shaders" "$pinnacle_dir/host64" "$game_dir/" || return 1
  if ((first)); then
    cp -f -- "$pinnacle_dir"/{PinancleofView-DFC.ini,ReShade.ini,dlss5-feed.cfg} "$game_dir/" || return 1
    cp -a -- "$pinnacle_dir/scripts/." "$game_dir/scripts/" || return 1
  else
    # Keep in-game ReShade and plugin tweaks; refresh only the plugins.
    cp -rn -- "$pinnacle_dir/scripts/." "$game_dir/scripts/" || return 1
    cp -f -- "$pinnacle_dir"/scripts/*.asi "$game_dir/scripts/" || return 1
  fi
  # The pack ships the author's logs and crash dump.
  rm -f -- "$game_dir"/host64/*.log "$game_dir"/host64/*.dmp "$game_dir/scripts/modupdater.log"
  # The updater downloads and replaces plugins at launch.
  [[ -f $game_dir/scripts/modupdater.asi ]] && mv -f -- "$game_dir/scripts/modupdater.asi" "$game_dir/scripts/modupdater.asi.off"
  sed -i 's/^\(ImproveGamepadSupport = \)[0-9]/\12/' "$game_dir/scripts/NFSUnderground2.WidescreenFix.ini"
  sed -i 's|^IntermediateCachePath=.*|IntermediateCachePath=.\\reshade-cache\r|; s/^EnableProxyLibrary=1/EnableProxyLibrary=0/' \
    "$game_dir/ReShade.ini"
  say "Pinnacle of View files installed$( ((first)) && printf ' (first install)')"
}

install_dxvk() {
  [[ -f $pinnacle_dir/d3d9.dll ]] || { warn "missing $pinnacle_dir/d3d9.dll"; return 1; }
  local tmp; tmp=$(mktemp) || return 1
  python3 -I "$component_dir/patch_dxvk.py" "$pinnacle_dir/d3d9.dll" "$tmp" >/dev/null || { rm -f -- "$tmp"; return 1; }
  if same "$tmp" "$game_dir/d3d9.dll"; then
    rm -f -- "$tmp"; say "Patched DXVK d3d9.dll already installed"
  else
    install -m644 -- "$tmp" "$game_dir/d3d9.dll" && rm -f -- "$tmp" || return 1
    say "Patched DXVK d3d9.dll installed"
  fi
}

install_loader() {
  [[ -f $vulkan_zip ]] || { warn "Vulkan runtime not found: $vulkan_zip (see README.md; set NFSU2_VULKAN_RT_ZIP)"; return 1; }
  local tmp; tmp=$(mktemp) || return 1
  unzip -p "$vulkan_zip" '*/x86/vulkan-1.dll' >"$tmp" && [[ -s $tmp ]] || { rm -f -- "$tmp"; warn "$vulkan_zip has no x86/vulkan-1.dll"; return 1; }
  same "$tmp" "$game_dir/vulkan-1.dll" || install -m644 -- "$tmp" "$game_dir/vulkan-1.dll" || { rm -f -- "$tmp"; return 1; }
  rm -f -- "$tmp"
  same "$layer_src" "$layer_dst" || install -m644 -- "$layer_src" "$layer_dst" || return 1
  say "Khronos vulkan-1.dll and the ReShade layer manifest installed"
}

install_registry() {
  [[ -d $prefix ]] || { warn "no Proton prefix: $prefix (launch the SPEED2.exe shortcut once)"; return 1; }
  [[ -x $proton ]] || { warn "Proton not found: $proton (set NFSU2_PROTON)"; return 1; }
  local dll
  for dll in dinput8 vulkan-1; do
    reg_has "$prefix/user.reg" "$overrides_key" "\"$dll\"=\"native,builtin\"" ||
      proton_reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native,builtin /f
  done
  reg_has "$prefix/system.reg" "$layers_key" "$(layer_line)" ||
    proton_reg add 'HKLM\Software\Khronos\Vulkan\ImplicitLayers' /v "$(win_path "$layer_dst")" /t REG_DWORD /d 0 /f /reg:32
  reg_has "$prefix/user.reg" "$overrides_key" '"vulkan-1"="native,builtin"' &&
    reg_has "$prefix/system.reg" "$layers_key" "$(layer_line)" || { warn "registry entries did not save"; return 1; }
  say "Prefix overrides and ReShade Vulkan layer registered"
}

install_component() {
  if game_running; then warn "NFSU2 is running; close it and rerun"; return 1; fi
  local failed=() step
  for step in files dxvk loader registry; do
    "install_$step" || failed+=("$step")
  done
  ((${#failed[@]} == 0)) || { warn "steps that need attention: ${failed[*]}"; return 1; }
}

uninstall_component() {
  if game_running; then warn "NFSU2 is running; close it and rerun"; return 1; fi
  rm -f -- "$game_dir/d3d9.dll" "$game_dir/vulkan-1.dll" "$layer_dst"
  if [[ -x $proton && -d $prefix ]]; then
    proton_reg delete 'HKLM\Software\Khronos\Vulkan\ImplicitLayers' /v "$(win_path "$layer_dst")" /f /reg:32
    proton_reg delete 'HKCU\Software\Wine\DllOverrides' /v vulkan-1 /f
  fi
  say "Removed the ReShade/DXVK chain (d3d9.dll, vulkan-1.dll, layer). The other Pinnacle"
  say "files and the dinput8 override (ASI loader) are left in place."
}

check_component() {
  local failures=0
  ok() { printf 'OK   nfsu2: %s\n' "$*"; }
  fail() { printf 'FAIL nfsu2: %s\n' "$*"; failures=$((failures + 1)); }

  if [[ ! -f $game_dir/SPEED2.exe ]]; then fail "game not found: $game_dir"; return "$failures"; fi
  [[ -f $game_dir/reshade32.dll && -d $game_dir/reshade-shaders ]] && ok "Pinnacle of View installed" \
    || fail "Pinnacle of View files missing"
  dxvk_patched "$game_dir/d3d9.dll" && ok "d3d9.dll is DXVK patched to load vulkan-1.dll" \
    || fail "d3d9.dll is missing or not the patched DXVK"
  [[ -f $game_dir/vulkan-1.dll ]] && ok "Khronos vulkan-1.dll installed" || fail "vulkan-1.dll missing"
  same "$layer_src" "$layer_dst" && ok "ReShade layer manifest installed" || fail "layer manifest missing: $layer_dst"
  grep -q '^EnableProxyLibrary=0' "$game_dir/ReShade.ini" 2>/dev/null && ok "ReShade proxy off" \
    || fail "ReShade.ini proxy is on or the file is missing"
  [[ -f $game_dir/scripts/NFSU2ExtraOptions.asi ]] && ok "ExtraOptions present" \
    || fail "scripts/NFSU2ExtraOptions.asi missing: the game does not start without it"
  [[ ! -f $game_dir/scripts/modupdater.asi ]] && ok "mod updater disabled" || fail "scripts/modupdater.asi is enabled"
  grep -q '^ImproveGamepadSupport = 2' "$game_dir/scripts/NFSUnderground2.WidescreenFix.ini" 2>/dev/null \
    && ok "PlayStation button prompts" || fail "WidescreenFix ImproveGamepadSupport is not 2"
  local dll
  for dll in dinput8 vulkan-1; do
    reg_has "$prefix/user.reg" "$overrides_key" "\"$dll\"=\"native,builtin\"" && ok "prefix loads native $dll" \
      || fail "prefix lacks $dll=native,builtin"
  done
  reg_has "$prefix/system.reg" "$layers_key" "$(layer_line)" && ok "ReShade Vulkan layer registered" \
    || fail "ReShade32.json is not a registered implicit layer"
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) printf 'ERROR nfsu2: unknown action %s (install|check|dry-run|uninstall)\n' "$action" >&2; exit 2 ;;
esac
