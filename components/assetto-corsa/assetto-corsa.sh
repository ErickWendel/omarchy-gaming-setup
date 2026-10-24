#!/usr/bin/env bash
# Assetto Corsa + Content Manager + CSP under Proton: install|check|dry-run|uninstall.
# install edits Steam's config, so it needs Steam closed; it never deletes the
# Proton prefix. Creating a new prefix is a manual step (see README.md).
# check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
appid=244210
steam_root=${AC_STEAM_ROOT:-$HOME/.local/share/Steam}
game_dir=${AC_GAME_DIR:-$steam_root/steamapps/common/assettocorsa}
prefix=${AC_PREFIX:-$steam_root/steamapps/compatdata/$appid/pfx}
proton9=${AC_PROTON9:-$steam_root/steamapps/common/Proton 9.0 (Beta)/proton}
compat_tool=proton_9
bin_dir=${AC_BIN_DIR:-$HOME/.local/bin}
wrapper_src="$component_dir/ac-steam-wrapper"
wrapper_dst="$bin_dir/ac-steam-wrapper"
hypr_dir=${AC_HYPR_DIR:-$HOME/.config/hypr}
rule_src="$component_dir/assettocorsa.lua"
rule_dst="$hypr_dir/assettocorsa.lua"
require_line='require("hypr.assettocorsa")'
cm_exe=${AC_CM_EXE:-$HOME/Downloads/content-manager/Content Manager.exe}
fonts_zip=${AC_FONTS_ZIP:-$HOME/Downloads/asseto/ac-fonts.zip}
fonts_dir="$game_dir/content/fonts/system"
backup_root=${AC_BACKUP_DIR:-$HOME/.local/state/omarchy-gaming-setup/backups}
steam_process=${AC_STEAM_PROCESS:-steam}
protontricks=${AC_PROTONTRICKS:-protontricks}
verbs=(vcrun2019 d3dcompiler_43 d3dx11_43 d3dcompiler_47 corefonts dotnet48)
# logitech-trueforce-dkms: logi-launch feeds AC's telemetry to logi-tf-sim
# (G923 rev lights, simulated TrueForce); added when it is installed.
logi_launch=${AC_LOGI_LAUNCH:-/usr/bin/logi-launch}
launch_command=$wrapper_dst
[[ -x $logi_launch ]] && launch_command+=" logi-launch"
# dxgi: ReShade; dwrite: CSP; xalia: a Proton helper that kept sessions alive.
launch_options="WINEDLLOVERRIDES=\"dxgi=n,b;dwrite=n,b\" PROTON_USE_XALIA=0 $launch_command %command%"

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN assetto-corsa: %s\n' "$*" >&2; }
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }
steam_running() { pgrep -x "$steam_process" >/dev/null 2>&1; }
game_running() { pgrep -f 'assettocorsa[\\/](acs|AssettoCorsa)\.exe' >/dev/null 2>&1; }
localconfigs() {
  find "$steam_root/userdata" -mindepth 3 -maxdepth 3 -path "*/userdata/${STEAM_USER_ID:-*}/config/localconfig.vdf" -type f 2>/dev/null
}
missing_verbs() {
  local verb
  for verb in "${verbs[@]}"; do
    grep -qx "$verb" "$prefix/winetricks.log" 2>/dev/null || printf '%s\n' "$verb"
  done
}
# The .NET installers switch the prefix to Windows 7/XP; CSP crashes there.
windows_version() {
  grep -xE 'win(xp|7|8|81|10|11)' "$prefix/winetricks.log" 2>/dev/null | tail -1
}

dry_run() {
  say "Install launch wrapper: $wrapper_dst"
  say "Install Content Manager window rule: $rule_dst (+ $require_line)"
  say "Content Manager as the Steam launcher: $game_dir/AssettoCorsa.exe (original kept as AssettoCorsa_original.exe)"
  say "CSP fonts: $fonts_dir from $fonts_zip"
  say "Steam launch options (Steam closed): $launch_options"
  say "Steam compatibility tool: $compat_tool"
  say "Prefix components: ${verbs[*]}, then win10"
}

install_wrapper() {
  same "$wrapper_src" "$wrapper_dst" || install -Dm755 "$wrapper_src" "$wrapper_dst" || return 1
  say "Launch wrapper installed: $wrapper_dst"
}

install_rule() {
  local config="$hypr_dir/hyprland.lua"
  [[ -f $config ]] || { warn "missing Hyprland config: $config"; return 1; }
  same "$rule_src" "$rule_dst" || install -Dm644 "$rule_src" "$rule_dst" || return 1
  if ! grep -Fxq "$require_line" "$config"; then
    printf '\n-- Assetto Corsa window rules managed by omarchy-gaming-setup.\n%s\n' "$require_line" >>"$config"
  fi
  if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null
    local errors; errors=$(hyprctl configerrors)
    [[ -z $errors ]] || { warn "Hyprland config errors: $errors"; return 1; }
  fi
  say "Content Manager window rule installed: $rule_dst"
}

install_content_manager() {
  [[ -d $game_dir ]] || { warn "Assetto Corsa is not installed: $game_dir"; return 1; }
  if [[ -e $game_dir/AssettoCorsa_original.exe ]]; then
    # Content Manager updates itself in place; never downgrade it.
    say "Content Manager is already the Steam launcher"
    return 0
  fi
  [[ -f $cm_exe ]] || { warn "Content Manager not found: $cm_exe (set AC_CM_EXE)"; return 1; }
  mv -n -- "$game_dir/AssettoCorsa.exe" "$game_dir/AssettoCorsa_original.exe" || return 1
  cp -- "$cm_exe" "$game_dir/AssettoCorsa.exe" || return 1
  say "Content Manager installed as $game_dir/AssettoCorsa.exe"
}

install_fonts() {
  [[ -d $game_dir ]] || return 1
  [[ -f $fonts_dir/segoeui.ttf ]] && { say "CSP fonts already installed"; return 0; }
  [[ -f $fonts_zip ]] || { warn "CSP font archive not found: $fonts_zip (set AC_FONTS_ZIP)"; return 1; }
  unzip -qn "$fonts_zip" 'system/*' -d "$game_dir/content/fonts" || return 1
  [[ -f $fonts_dir/segoeui.ttf ]] || { warn "$fonts_zip has no system/segoeui.ttf"; return 1; }
  say "CSP fonts installed: $fonts_dir"
}

install_steam_config() {
  [[ -x $proton9 ]] || warn "Proton 9.0 is not installed; install it with: steam steam://install/2805730"
  if steam_running; then
    warn "Steam is running; exit Steam and rerun to set launch options and Proton 9.0"
    return 1
  fi
  local configs
  mapfile -t configs < <(localconfigs)
  ((${#configs[@]} == 1)) || { warn "expected one Steam localconfig.vdf, found ${#configs[@]} (set STEAM_USER_ID)"; return 1; }
  python3 -I "$component_dir/configure_steam.py" --localconfig "${configs[0]}" \
    --config "$steam_root/config/config.vdf" --appid "$appid" \
    --launch-options "$launch_options" --compat-tool "$compat_tool" --backup-dir "$backup_root"
}

install_prefix() {
  if [[ ! -d $prefix ]]; then
    warn "no Proton prefix yet: create it once with GE-Proton9-20 (see components/assetto-corsa/README.md)"
    return 1
  fi
  if game_running; then
    warn "Assetto Corsa is running; close it and rerun to install prefix components"
    return 1
  fi
  local missing
  mapfile -t missing < <(missing_verbs)
  if ((${#missing[@]})); then
    "$protontricks" "$appid" -q "${missing[@]}" || { warn "protontricks failed: ${missing[*]}"; return 1; }
  fi
  if [[ $(windows_version) != win10 ]]; then
    "$protontricks" "$appid" -q win10 || { warn "protontricks win10 failed"; return 1; }
  fi
  say "Prefix components installed; Windows version is win10"
}

install_component() {
  local failed=() step
  for step in wrapper rule content_manager fonts steam_config prefix; do
    "install_$step" || failed+=("$step")
  done
  ((${#failed[@]} == 0)) || { warn "steps that need attention: ${failed[*]}"; return 1; }
}

uninstall_component() {
  rm -f -- "$wrapper_dst" "$rule_dst"
  if [[ -f $hypr_dir/hyprland.lua ]]; then
    sed -i "/^-- Assetto Corsa window rules managed by omarchy-gaming-setup\.$/d; /^require(\"hypr\.assettocorsa\")$/d" \
      "$hypr_dir/hyprland.lua"
  fi
  if [[ -f $game_dir/AssettoCorsa_original.exe ]]; then
    mv -f -- "$game_dir/AssettoCorsa_original.exe" "$game_dir/AssettoCorsa.exe"
    say "Restored the original AssettoCorsa.exe"
  fi
  say "Removed the wrapper and window rule. Steam launch options, Proton version and"
  say "prefix are left as they are; restore them from $backup_root if needed."
}

check_component() {
  local failures=0 configs missing
  ok() { printf 'OK   assetto-corsa: %s\n' "$*"; }
  fail() { printf 'FAIL assetto-corsa: %s\n' "$*"; failures=$((failures + 1)); }

  same "$wrapper_src" "$wrapper_dst" && ok "launch wrapper installed" || fail "launch wrapper missing or outdated: $wrapper_dst"
  same "$rule_src" "$rule_dst" && grep -Fxq "$require_line" "$hypr_dir/hyprland.lua" 2>/dev/null \
    && ok "Content Manager window rule installed" || fail "window rule missing: $rule_dst"
  [[ -e $game_dir/AssettoCorsa_original.exe ]] && ok "Content Manager is the Steam launcher" \
    || fail "Content Manager is not installed as AssettoCorsa.exe"
  [[ -f $fonts_dir/segoeui.ttf ]] && ok "CSP fonts installed" || fail "CSP font missing: $fonts_dir/segoeui.ttf"
  [[ -x $proton9 ]] && ok "Proton 9.0 installed" || fail "Proton 9.0 missing (steam steam://install/2805730)"

  mapfile -t configs < <(localconfigs)
  if ((${#configs[@]} == 1)) && grep -Fq "$launch_command %command%" "${configs[0]}"; then
    ok "Steam launch options use the wrapper${launch_command#"$wrapper_dst"}"
  else
    fail "Steam launch options do not use $launch_command (exit Steam and rerun install)"
  fi
  if awk '/"CompatToolMapping"/{m=1} m && /"'"$appid"'"/{a=1} a && /"name"/{print; exit}' \
      "$steam_root/config/config.vdf" 2>/dev/null | grep -q "\"$compat_tool\""; then
    ok "Steam uses $compat_tool for Assetto Corsa"
  else
    fail "Steam compatibility tool is not $compat_tool"
  fi

  if [[ -d $prefix ]]; then
    mapfile -t missing < <(missing_verbs)
    ((${#missing[@]} == 0)) && ok "prefix components installed" || fail "prefix lacks: ${missing[*]}"
    [[ $(windows_version) == win10 ]] && ok "prefix is win10" || fail "prefix is not win10 (CSP crashes on win7)"
  else
    fail "no Proton prefix: $prefix"
  fi
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) printf 'ERROR assetto-corsa: unknown action %s (install|check|dry-run|uninstall)\n' "$action" >&2; exit 2 ;;
esac
