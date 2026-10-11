#!/usr/bin/env bash
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../config/machine.example.env
source "$config_file"

action=${1:-install}
profile_name=${OPENRGB_PROFILE%.orp}
profile_path="$HOME/.config/OpenRGB/$profile_name.orp"
unit_path="$HOME/.config/systemd/user/openrgb.service"
legacy_path="$HOME/.config/autostart/OpenRGB.desktop"
disabled_legacy="$legacy_path.disabled-by-omarchy-gaming-setup"
profile_asset="$repo_dir/assets/openrgb/static-green.orp.base64"
unit_asset="$repo_dir/systemd/user/openrgb.service"
backup_root=${OMARCHY_BACKUP_ROOT:-$HOME/.local/state/omarchy-gaming-setup/backups}
openrgb_bin=${OPENRGB_BIN:-/usr/bin/openrgb}
decoded_profile=

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR OpenRGB: %s\n' "$*" >&2; exit 1; }

backup_once() {
  local source=$1 relative=${1#"$HOME"/} destination
  [[ -e "$source" || -L "$source" ]] || return 0
  destination="$backup_root/$relative"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  mkdir -p -- "$(dirname -- "$destination")"
  cp -a -- "$source" "$destination"
  say "Backed up $source to $destination"
}

validate_sources() {
  [[ -x "$openrgb_bin" ]] || die "binary not found or not executable: $openrgb_bin"
  [[ -r "$profile_asset" ]] || die "versioned profile is missing: $profile_asset"
  [[ -r "$unit_asset" ]] || die "service unit is missing: $unit_asset"
  command -v base64 >/dev/null 2>&1 || die "base64 is required to install the profile"
}

dry_run() {
  say "OpenRGB binary: $openrgb_bin"
  say "Install profile: $profile_path"
  say "Install and enable service: $unit_path"
  say "Disable legacy autostart if present: $legacy_path"
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
  check_message="legacy XDG autostart is inactive"; check_item test ! -e "$legacy_path"
  return "$failures"
}

install_component() {
  local graphical_session=false
  validate_sources
  decoded_profile=$(mktemp)
  trap '[[ -z ${decoded_profile:-} ]] || rm -f -- "$decoded_profile"' EXIT
  base64 --decode "$profile_asset" >"$decoded_profile" || die "versioned profile cannot be decoded"
  LC_ALL=C grep -a -q '^OPENRGB_PROFILE' "$decoded_profile" || die "versioned profile has an invalid header"

  mkdir -p -- "$(dirname -- "$profile_path")" "$(dirname -- "$unit_path")"
  systemctl --user stop openrgb.service >/dev/null 2>&1 || true

  if [[ -e "$profile_path" ]] && ! cmp -s -- "$profile_path" "$decoded_profile"; then
    backup_once "$profile_path"
  fi
  if [[ -e "$unit_path" ]] && ! cmp -s -- "$unit_path" "$unit_asset"; then
    backup_once "$unit_path"
  fi
  backup_once "$legacy_path"

  # OpenRGB maintains its own XDG autostart setting and will recreate the
  # desktop entry when merely moved away. Disable that supported mechanism
  # before the managed service starts.
  "$openrgb_bin" --autostart-disable >/dev/null 2>&1 || die "failed to disable OpenRGB's built-in autostart"

  if [[ -e "$legacy_path" || -L "$legacy_path" ]]; then
    if [[ -e "$disabled_legacy" || -L "$disabled_legacy" ]]; then
      cmp -s -- "$legacy_path" "$disabled_legacy" || die "active and disabled legacy autostart entries differ"
      unlink -- "$legacy_path"
      say "Removed duplicate legacy autostart recreated by OpenRGB"
    else
      mv -- "$legacy_path" "$disabled_legacy"
      say "Disabled legacy autostart: $disabled_legacy"
    fi
  fi

  install -m 0644 -- "$decoded_profile" "$profile_path"
  install -m 0644 -- "$unit_asset" "$unit_path"
  systemctl --user daemon-reload || die "failed to reload the user service manager"
  systemctl --user enable openrgb.service || die "failed to enable openrgb.service"

  if [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && systemctl --user is-active --quiet graphical-session.target; then
    graphical_session=true
  fi
  if [[ "$graphical_session" == true ]]; then
    if pgrep -x openrgb >/dev/null 2>&1; then
      pkill -TERM -x openrgb || die "failed to stop the existing unmanaged OpenRGB process"
      for _ in 1 2 3 4 5; do
        pgrep -x openrgb >/dev/null 2>&1 || break
        sleep 1
      done
      pgrep -x openrgb >/dev/null 2>&1 && die "existing OpenRGB process did not stop"
    fi
    systemctl --user restart openrgb.service || die "failed to start openrgb.service"
    say "Installed and started OpenRGB with $profile_name.orp"
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
