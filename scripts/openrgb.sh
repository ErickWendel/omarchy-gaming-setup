#!/usr/bin/env bash
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../config/machine.example.env
source "$config_file"

action=${1:-install}
profile_name=${OPENRGB_PROFILE%.json}
profile_name=${profile_name%.orp}
# OpenRGB 1.1 keeps profiles as JSON under profiles/ and loads them by name.
profile_path="$HOME/.config/OpenRGB/profiles/$profile_name.json"
openrgb_config="$HOME/.config/OpenRGB/OpenRGB.json"
unit_path="$HOME/.config/systemd/user/openrgb.service"
legacy_path="$HOME/.config/autostart/OpenRGB.desktop"
profile_asset="$repo_dir/assets/openrgb/static-green.json"
unit_asset="$repo_dir/systemd/user/openrgb.service"
autostart_helper="$repo_dir/scripts/set-openrgb-autostart.py"
openrgb_bin=${OPENRGB_BIN:-/usr/bin/openrgb}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR OpenRGB: %s\n' "$*" >&2; exit 1; }

# shellcheck source=lib/common.sh
source "$repo_dir/scripts/lib/common.sh"

validate_sources() {
  [[ -x "$openrgb_bin" ]] || die "binary not found or not executable: $openrgb_bin"
  [[ -r "$profile_asset" ]] || die "versioned profile is missing: $profile_asset"
  [[ -r "$unit_asset" ]] || die "service unit is missing: $unit_asset"
  [[ -r "$autostart_helper" ]] || die "autostart helper is missing: $autostart_helper"
  command -v python3 >/dev/null 2>&1 || die "python3 is required to update OpenRGB's configuration"
}

dry_run() {
  say "OpenRGB binary: $openrgb_bin"
  say "Install profile: $profile_path"
  say "Install and enable service: $unit_path"
  say "Remove legacy autostart (with backup) if present: $legacy_path"
  say "Disable internal autostart without launching OpenRGB: $openrgb_config"
  say "Backups: $backup_root"
}

check() {
  local failures=0 process_count
  check_item() {
    if "$@"; then printf 'OK   OpenRGB: %s\n' "$check_message"
    else printf 'WARN OpenRGB: %s\n' "$check_message"; failures=$((failures + 1)); fi
  }

  check_message="binary is executable ($openrgb_bin)"; check_item test -x "$openrgb_bin"
  check_message="profile is installed ($profile_path)"; check_item test -s "$profile_path"
  check_message="user service is installed ($unit_path)"; check_item test -s "$unit_path"
  check_message="user service is enabled"; check_item systemctl --user is-enabled --quiet openrgb.service
  check_message="user service is active"; check_item systemctl --user is-active --quiet openrgb.service
  process_count=$(pgrep -x openrgb 2>/dev/null | wc -l)
  check_message="exactly one openrgb process is running (found $process_count)"; check_item test "$process_count" -eq 1
  check_message="legacy XDG autostart is inactive"
  check_item test ! -e "$legacy_path" -a ! -e "$legacy_path$legacy_disabled_suffix"
  return "$failures"
}

install_component() {
  validate_sources
  python3 -c 'import json, sys; json.load(open(sys.argv[1]))["controllers"]' "$profile_asset" \
    || die "versioned profile is not an OpenRGB 1.1 profile: $profile_asset"

  mkdir -p -- "$(dirname -- "$profile_path")" "$(dirname -- "$unit_path")"
  systemctl --user stop openrgb.service >/dev/null 2>&1 || true

  if [[ -e "$profile_path" ]] && ! cmp -s -- "$profile_path" "$profile_asset"; then
    backup_once "$profile_path"
  fi
  if [[ -e "$unit_path" ]] && ! cmp -s -- "$unit_path" "$unit_asset"; then
    backup_once "$unit_path"
  fi
  backup_once "$openrgb_config"

  # Do not use `openrgb --autostart-disable` here. OpenRGB 1.0rc3 performs
  # hardware discovery even for that option and can segfault inside libusb.
  # Editing the setting atomically avoids touching USB devices during setup.
  python3 "$autostart_helper" "$openrgb_config" || die "failed to disable OpenRGB's internal autostart setting"

  retire_autostart_entry "$legacy_path"

  install -m 0644 -- "$profile_asset" "$profile_path"
  install -m 0644 -- "$unit_asset" "$unit_path"
  systemctl --user daemon-reload || die "failed to reload the user service manager"
  systemctl --user enable openrgb.service || die "failed to enable openrgb.service"

  if graphical_session_active; then
    if pgrep -x openrgb >/dev/null 2>&1; then
      pkill -TERM -x openrgb || die "failed to stop the existing unmanaged OpenRGB process"
      for _ in 1 2 3 4 5; do
        pgrep -x openrgb >/dev/null 2>&1 || break
        sleep 1
      done
      pgrep -x openrgb >/dev/null 2>&1 && die "existing OpenRGB process did not stop"
    fi
    systemctl --user restart openrgb.service || die "failed to start openrgb.service"
    say "Installed and started OpenRGB with the $profile_name profile"
  else
    say "Installed and enabled OpenRGB; start is deferred until the next graphical login"
  fi
}

case "$action" in
  install) install_component ;;
  check) check ;;
  dry-run) dry_run ;;
  *) die "unknown action '$action' (expected install, check, or dry-run)" ;;
esac
