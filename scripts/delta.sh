#!/usr/bin/env bash
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

action=${1:-install}
shift || true
archive=
while (($#)); do
  case "$1" in
    --archive)
      shift
      [[ -n ${1:-} ]] || { printf 'ERROR Delta: --archive requires a path\n' >&2; exit 2; }
      archive=$1
      ;;
    *) printf 'ERROR Delta: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# The unit's ExecStart uses %h/.local/opt/delta-center, so this path is fixed.
install_dir="$HOME/.local/opt/delta-center"
binary="$install_dir/delta-center"
launcher="$install_dir/delta-center-launch"
archive_stamp="$install_dir/.omarchy-archive-sha256"
unit_name=delta-center.service
unit_path="$HOME/.config/systemd/user/$unit_name"
unit_asset="$repo_dir/systemd/user/$unit_name"
autostart_dir="$HOME/.config/autostart"
legacy_path="$autostart_dir/delta-center.desktop"
desktop_path="$HOME/.local/share/applications/delta-center.desktop"
remediation="install the Delta runtime first, e.g. ./setup.sh --delta-archive /path/to/delta-center-linux-compat-x64.tar.gz"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR Delta: %s\n' "$*" >&2; exit 1; }
# shellcheck source=lib/common.sh
source "$repo_dir/scripts/lib/common.sh"

# Main Delta processes started from this runtime. Electron helpers share the
# binary path but carry --type=; unrelated Electron apps never match.
delta_main_pids() {
  local pid args
  for pid in $(pgrep -f -- "$install_dir/delta-center" 2>/dev/null); do
    args=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || continue
    [[ "$args" == "$binary "* || "$args" == "$binary" ]] || continue
    [[ "$args" == *" --type="* ]] && continue
    printf '%s\n' "$pid"
  done
}

# Generated autostart units that still have a source entry or are running.
autostart_units() {
  systemctl --user list-units --all --plain --no-legend 'app-delta*@autostart.service' 2>/dev/null | \
    awk '$2 == "loaded" || $3 == "active" { print $1 }'
}

# Every file the XDG autostart generator would read that launches Delta.
autostart_references() {
  [[ -d "$autostart_dir" ]] || return 0
  grep -l -s -F -- "$install_dir/" "$autostart_dir"/* 2>/dev/null
  autostart_units
}

dry_run() {
  [[ -z "$archive" ]] || say "Install Delta runtime from archive: $archive -> $install_dir"
  say "Delta launcher: $launcher"
  say "Install and enable service: $unit_path ($(sed -n 's/^ExecStart=//p' "$unit_asset"))"
  say "Remove XDG autostart entries (with backups): $legacy_path"
  say "Keep application-menu launcher: $desktop_path"
  say "Backups: $backup_root"
}

check() {
  local failures=0 pid count exec_line references
  check_item() {
    if "$@"; then printf 'OK   Delta: %s\n' "$check_message"
    else printf 'WARN Delta: %s\n' "$check_message"; failures=$((failures + 1)); fi
  }

  check_message="runtime is installed ($binary)"; check_item test -x "$binary"
  check_message="launcher is executable ($launcher)"; check_item test -x "$launcher"
  check_message="user service is installed ($unit_path)"; check_item test -s "$unit_path"
  check_message="user service starts with --hidden"
  check_item grep -q '^ExecStart=.*delta-center-launch --hidden$' "$unit_path"
  check_message="user service is enabled"; check_item systemctl --user is-enabled --quiet "$unit_name"
  check_message="user service is wanted by graphical-session.target"
  check_item test -L "$HOME/.config/systemd/user/graphical-session.target.wants/$unit_name"
  check_message="user service is active"; check_item systemctl --user is-active --quiet "$unit_name"

  pid=$(systemctl --user show -p MainPID --value "$unit_name" 2>/dev/null)
  check_message="running service command includes --hidden (MainPID ${pid:-none})"
  check_item grep -qz -- '^--hidden$' "/proc/${pid:-0}/cmdline"
  count=$(delta_main_pids | wc -l)
  check_message="exactly one Delta Center instance is running (found $count)"; check_item test "$count" -eq 1

  references=$(autostart_references | tr '\n' ' ')
  check_message="no XDG autostart entry launches Delta${references:+ (found: $references)}"
  check_item test -z "$references"

  exec_line=$(sed -n 's/^Exec=//p' "$desktop_path" 2>/dev/null)
  check_message="application-menu launcher opens the UI ($desktop_path)"
  check_item test "$exec_line" = "$launcher"
  return "$failures"
}

install_runtime_from_archive() {
  local sha staging root
  [[ -f "$archive" && -r "$archive" ]] || die "archive not found or unreadable: $archive"
  sha=$(sha256sum -- "$archive" | awk '{ print $1 }') || die "failed to hash $archive"
  if [[ -x "$binary" && -f "$archive_stamp" && "$(<"$archive_stamp")" == "$sha" ]]; then
    say "Delta runtime already installed from this archive"
    return 0
  fi

  mkdir -p -- "$(dirname -- "$install_dir")" || die "failed to create $(dirname -- "$install_dir")"
  staging=$(mktemp -d "$install_dir.new.XXXXXX") || die "failed to create a staging directory"
  if ! tar -xzf "$archive" -C "$staging"; then
    rm -rf -- "$staging"
    die "failed to extract $archive"
  fi
  root=$(find "$staging" -maxdepth 2 -type f -name delta-center -printf '%h\n' | head -n 1)
  if [[ -z "$root" ]]; then
    rm -rf -- "$staging"
    die "archive does not contain a delta-center executable: $archive"
  fi
  chmod +x -- "$root/delta-center"

  # Keep the existing launcher: it carries this machine's compatibility flags.
  if [[ -x "$launcher" && ! -e "$root/delta-center-launch" ]]; then
    cp -a -- "$launcher" "$root/delta-center-launch"
  fi
  if [[ ! -e "$root/delta-center-launch" ]]; then
    printf '%s\n' '#!/usr/bin/env bash' \
      "exec \"$binary\" \\" '  --disable-setuid-sandbox \' '  --ozone-platform=x11 \' '  "$@"' \
      >"$root/delta-center-launch"
    chmod 0755 -- "$root/delta-center-launch"
  fi
  printf '%s\n' "$sha" >"$root/.omarchy-archive-sha256"

  if [[ -e "$install_dir" ]]; then
    local previous="$backup_root/.local/opt/delta-center.$(date +%Y%m%d%H%M%S)"
    mkdir -p -- "$(dirname -- "$previous")" || die "failed to create runtime backup directory"
    mv -- "$install_dir" "$previous" || die "failed to move the previous runtime to $previous"
    say "Moved previous Delta runtime to $previous"
  fi
  mv -- "$root" "$install_dir" || die "failed to install runtime into $install_dir"
  rm -rf -- "$staging"
  say "Installed Delta runtime from $archive"
}

stop_existing_instances() {
  local unit pids
  systemctl --user stop "$unit_name" >/dev/null 2>&1 || true
  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    if systemctl --user is-active --quiet "$unit"; then
      systemctl --user stop "$unit" >/dev/null 2>&1 && say "Stopped legacy autostart instance $unit"
    fi
    systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  done < <(autostart_units)

  pids=$(delta_main_pids)
  [[ -z "$pids" ]] && return 0
  # shellcheck disable=SC2086 # one PID per word
  kill -TERM $pids 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -z "$(delta_main_pids)" ]] && { say "Stopped unmanaged Delta Center instance"; return 0; }
    sleep 1
  done
  die "existing Delta Center process did not stop: $(delta_main_pids | tr '\n' ' ')"
}

install_desktop_entry() {
  [[ -e "$desktop_path" || -L "$desktop_path" ]] && return 0
  mkdir -p -- "$(dirname -- "$desktop_path")" || die "failed to create $(dirname -- "$desktop_path")"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Delta Center (CW360LCD)' \
    "Exec=$launcher" "Icon=$install_dir/resources/main/app.ico" 'Terminal=false' \
    'Categories=Utility;System;' 'StartupNotify=true' >"$desktop_path"
  chmod 0644 -- "$desktop_path"
  say "Installed application-menu launcher $desktop_path"
}

install_component() {
  [[ -r "$unit_asset" ]] || die "service unit is missing: $unit_asset"
  if [[ -n "$archive" ]]; then
    stop_existing_instances
    install_runtime_from_archive
  fi
  [[ -x "$binary" && -x "$launcher" ]] || die "runtime or launcher is missing at $install_dir; $remediation"

  stop_existing_instances
  # Retire autostart before enabling the unit so a failure can never leave
  # both startup paths active.
  retire_autostart_entry "$legacy_path"

  mkdir -p -- "$(dirname -- "$unit_path")" || die "failed to create $(dirname -- "$unit_path")"
  if [[ -e "$unit_path" ]] && ! cmp -s -- "$unit_path" "$unit_asset"; then
    backup_once "$unit_path"
  fi
  install -m 0644 -- "$unit_asset" "$unit_path" || die "failed to install $unit_path"
  install_desktop_entry

  systemctl --user daemon-reload || die "failed to reload the user service manager"
  systemctl --user enable "$unit_name" || die "failed to enable $unit_name"
  if graphical_session_active; then
    systemctl --user restart "$unit_name" || die "failed to start $unit_name"
    say "Installed and started Delta Center hidden under $unit_name"
  else
    say "Installed and enabled Delta Center; start is deferred until the next graphical login"
  fi
}

case "$action" in
  install) install_component ;;
  check) check ;;
  dry-run) dry_run ;;
  *) die "unknown action '$action' (expected install, check, or dry-run)" ;;
esac
