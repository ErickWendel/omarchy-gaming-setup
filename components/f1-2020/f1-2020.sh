#!/usr/bin/env bash
# F1 2020 with the G923 under Proton: install|check|dry-run|uninstall.
# install points the G923 brake at the axis Wine gives it, turns the game's UDP
# telemetry on for the rev-light bridge and starts that bridge as a user
# service. The game must be closed; check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
steam_root=${F1_2020_STEAM_ROOT:-$HOME/.local/share/Steam}
game_dir=${F1_2020_GAME_DIR:-$HOME/Games/F1 2020}
action_map="$game_dir/actionmaps/logitech_g923.xml"
bin_dir=${F1_2020_BIN_DIR:-$HOME/.local/bin}
unit_dir=${F1_2020_UNIT_DIR:-$HOME/.config/systemd/user}
bridge_src="$component_dir/f1-2020-rev-lights"
bridge_dst="$bin_dir/omarchy-f1-2020-rev-lights"
unit=omarchy-f1-2020-rev-lights.service
backup_root=${F1_2020_BACKUP_DIR:-$HOME/.local/state/omarchy-gaming-setup/backups}/f1-2020
# logi-tf-sim holds 20777 and reads only the F1 22-25 formats.
telemetry_port=20778

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN f1-2020: %s\n' "$*" >&2; }
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }
game_running() { pgrep -f 'F1_2020(_dx12)?\.exe' >/dev/null 2>&1; }
# The settings file sits in the prefix of whichever shortcut runs the game.
settings_file() {
  [[ -n ${F1_2020_SETTINGS:-} ]] && { printf '%s\n' "$F1_2020_SETTINGS"; return; }
  find "$steam_root/steamapps/compatdata" -mindepth 1 -maxdepth 1 -type d -exec sh -c \
    'f="$1/pfx/drive_c/users/steamuser/Documents/My Games/F1 2020/hardwaresettings/hardware_settings_config.xml"; [ -f "$f" ] && printf "%s\n" "$f"' _ {} \; | head -1
}
# Windows reports the G923 brake as Rz; Wine's SDL backend gives the wheel
# X steering, Y gas, Z brake and Rx clutch, so Rz does not exist.
map_uses_rz() { grep -q 'axisName="di_z_axis_rotation"' "$action_map"; }
udp_line() { grep -o '<udp [^>]*>' "$1"; }
udp_ready() { udp_line "$1" | grep -q "enabled=\"true\".*port=\"$telemetry_port\".*format=\"2020\""; }

dry_run() {
  say "Back up and rebind Brake from Rz to Z in $action_map"
  say "Turn UDP telemetry on in the game's hardware_settings_config.xml: 127.0.0.1:$telemetry_port, 60 Hz, 2020 format"
  say "Install $bridge_dst and enable the user service $unit"
}

install_component() {
  local failed=0 settings
  command -v logi-tf-sim >/dev/null 2>&1 || warn "logi-tf-sim is missing; run scripts/packages.sh install (logi-wheel)"
  if game_running; then
    warn "F1 2020 is running; close it and rerun (it rewrites its settings on exit)"
    return 1
  fi
  mkdir -p "$backup_root"

  if [[ ! -f $action_map ]]; then
    warn "no G923 action map at $action_map (set F1_2020_GAME_DIR)"; failed=1
  elif map_uses_rz; then
    cp -n "$action_map" "$backup_root/" &&
      sed -i 's/axisName="di_z_axis_rotation"/axisName="di_z_axis"/' "$action_map" &&
      say "G923 brake bound to Z (backup in $backup_root)" || failed=1
  else
    say "G923 brake already on Z"
  fi

  settings=$(settings_file)
  if [[ -z $settings ]]; then
    warn "hardware_settings_config.xml not found; start the game once, then rerun"; failed=1
  elif udp_ready "$settings"; then
    say "UDP telemetry already on"
  else
    cp -n "$settings" "$backup_root/" &&
      sed -i -E "/<udp /{s/enabled=\"[^\"]*\"/enabled=\"true\"/;s/ip=\"[^\"]*\"/ip=\"127.0.0.1\"/;s/port=\"[^\"]*\"/port=\"$telemetry_port\"/;s/sendRate=\"[^\"]*\"/sendRate=\"60\"/;s/format=\"[^\"]*\"/format=\"2020\"/}" "$settings" &&
      udp_ready "$settings" && say "UDP telemetry on: 127.0.0.1:$telemetry_port" || failed=1
  fi

  if install -Dm755 "$bridge_src" "$bridge_dst" && install -Dm644 "$component_dir/$unit" "$unit_dir/$unit"; then
    systemctl --user daemon-reload &&
      systemctl --user enable --quiet "$unit" &&
      systemctl --user restart "$unit" &&
      say "Rev-light bridge running: $unit" || failed=1
  else
    failed=1
  fi
  return "$failed"
}

uninstall_component() {
  systemctl --user disable --now --quiet "$unit" 2>/dev/null
  rm -f -- "$bridge_dst" "$unit_dir/$unit"
  systemctl --user daemon-reload
  say "Removed the rev-light bridge; the action map and settings backups are in $backup_root"
}

check_component() {
  local failures=0 settings
  ok() { printf 'OK   f1-2020: %s\n' "$*"; }
  fail() { printf 'FAIL f1-2020: %s\n' "$*"; failures=$((failures + 1)); }

  if [[ ! -f $action_map ]]; then
    fail "no G923 action map at $action_map"
  elif map_uses_rz; then
    fail "G923 brake is still bound to Rz (run install with the game closed)"
  else
    ok "G923 brake bound to Z"
  fi
  settings=$(settings_file)
  if [[ -n $settings ]] && udp_ready "$settings"; then
    ok "UDP telemetry on, port $telemetry_port"
  else
    fail "UDP telemetry off or on the wrong port (run install with the game closed)"
  fi
  same "$bridge_src" "$bridge_dst" && ok "rev-light bridge installed" || fail "bridge missing or outdated: $bridge_dst"
  systemctl --user is-active --quiet "$unit" && ok "$unit running" || fail "$unit not running"
  command -v logi-tf-sim >/dev/null 2>&1 && ok "logi-tf-sim installed" || fail "logi-tf-sim missing (package logi-wheel)"
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) printf 'ERROR f1-2020: unknown action %s (install|check|dry-run|uninstall)\n' "$action" >&2; exit 2 ;;
esac
