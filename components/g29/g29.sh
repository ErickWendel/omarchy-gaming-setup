#!/usr/bin/env bash
# Logitech G29 in PS4 mode: install|check|dry-run|uninstall.
# install and uninstall use sudo for the udev rule and its helper; check and
# dry-run never change the system or send anything to the wheel.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
sysfs_root=${G29_SYSFS_ROOT:-/sys}
helper_src="$component_dir/g29-ps4-modeswitch"
rule_src="$component_dir/71-omarchy-g29-ps4-mode.rules"
helper_dst=${G29_HELPER_DST:-/usr/local/lib/omarchy-gaming-setup/g29-ps4-modeswitch}
rule_dst=${G29_RULE_DST:-/etc/udev/rules.d/71-omarchy-g29-ps4-mode.rules}
# Session access to uinput and the wheels' hidraw nodes (Oversteer, Proton).
access_rule_src="$component_dir/60-lg4ff-userspace.rules"
access_rule_dst=${G29_ACCESS_RULE_DST:-/etc/udev/rules.d/60-lg4ff-userspace.rules}
backup_root=${OMARCHY_BACKUP_ROOT:-$HOME/.local/state/omarchy-gaming-setup/backups}
sudo_cmd=${G29_SUDO-sudo}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR G29: %s\n' "$*" >&2; exit 1; }

# Print "<hid dir> <product>" for every USB G29 in PS4 (c260) or native (c24f)
# mode. Only USB interface 0 carries the wheel; the driver leaves interface 1 unbound.
find_wheels() {
  local dir id
  for dir in "$sysfs_root"/bus/hid/devices/0003:046D:*; do
    [[ -d $dir && $(<"$dir/../bInterfaceNumber") == 00 ]] 2>/dev/null || continue
    id=${dir##*/0003:046D:}
    id=${id%%.*}
    case $id in C260|C24F) printf '%s %s\n' "$dir" "$id" ;; esac
  done
}

# Record the pre-install state once: a copy of the file, or an .absent marker,
# so a reinstall never mistakes our own managed file for the original.
backup_system_file() {
  local source=$1 destination="$backup_root/system${1}"
  [[ -e $destination || -e $destination.absent ]] && return 0
  mkdir -p -- "$(dirname -- "$destination")" || die "cannot create backup directory for $source"
  if [[ -e $source ]]; then
    cp -a -- "$source" "$destination" || die "cannot back up $source"
    say "Backed up $source to $destination"
  else
    : >"$destination.absent" || die "cannot record absent $source"
  fi
}

dry_run() {
  say "Install udev rule: $rule_dst"
  say "Install mode-switch helper: $helper_dst"
  say "Install wheel access rule: $access_rule_dst"
  say "Reload udev rules and switch any wheel currently in PS4 mode"
  say "Backups: $backup_root/system"
}

install_component() {
  [[ -r $helper_src && -r $rule_src && -r $access_rule_src ]] || die "component files are missing in $component_dir"
  command -v python3 >/dev/null 2>&1 || die "python3 is required by the mode-switch helper"
  backup_system_file "$helper_dst"
  backup_system_file "$rule_dst"
  backup_system_file "$access_rule_dst"
  $sudo_cmd install -Dm755 "$helper_src" "$helper_dst" || die "cannot install $helper_dst"
  $sudo_cmd install -Dm644 "$rule_src" "$rule_dst" || die "cannot install $rule_dst"
  $sudo_cmd install -Dm644 "$access_rule_src" "$access_rule_dst" || die "cannot install $access_rule_dst"
  $sudo_cmd udevadm control --reload || die "udev rules reload failed"
  local dir id node
  while read -r dir id; do
    [[ $id == C260 ]] || continue
    for node in "$dir"/hidraw/hidraw*; do
      [[ -e $node ]] || continue
      say "Switching connected G29 (${node##*/}) from PS4 mode to native mode"
      $sudo_cmd udevadm trigger --action=add "$sysfs_root/class/hidraw/${node##*/}"
    done
  done < <(find_wheels)
  $sudo_cmd udevadm settle --timeout=10 || true
  say "G29 PS4-mode support installed. Run: $0 check"
}

uninstall_component() {
  local path backup
  for path in "$rule_dst" "$helper_dst" "$access_rule_dst"; do
    backup="$backup_root/system$path"
    if [[ -e $backup ]]; then
      $sudo_cmd install -Dm"$(stat -c %a "$backup")" "$backup" "$path" || die "cannot restore $path"
      rm -f -- "$backup"
      say "Restored $path from $backup"
    elif [[ -e $path ]]; then
      $sudo_cmd rm -f -- "$path" || die "cannot remove $path"
      say "Removed $path"
    fi
    rm -f -- "$backup.absent"
  done
  $sudo_cmd udevadm control --reload || die "udev rules reload failed"
  say "Uninstalled. A wheel already in native mode stays there until it is replugged."
}

check_component() {
  local failures=0 dir id input name ff
  ok() { printf 'OK   G29: %s\n' "$*"; }
  fail() { printf 'FAIL G29: %s\n' "$*"; failures=$((failures + 1)); }
  info() { printf 'INFO G29: %s\n' "$*"; }

  if [[ -x $helper_dst ]] && cmp -s "$helper_src" "$helper_dst"; then
    ok "mode-switch helper installed"
  else
    fail "mode-switch helper missing or outdated: $helper_dst"
  fi
  if [[ -r $rule_dst ]] && cmp -s "$rule_src" "$rule_dst"; then
    ok "udev rule installed"
  else
    fail "udev rule missing or outdated: $rule_dst"
  fi
  if cmp -s "$access_rule_src" "$access_rule_dst" 2>/dev/null; then
    ok "wheel access rule installed"
  else
    fail "wheel access rule missing or outdated: $access_rule_dst"
  fi
  if command -v dkms >/dev/null 2>&1 && dkms status new-lg4ff 2>/dev/null | grep -q "$(uname -r).*installed"; then
    ok "new-lg4ff DKMS module is built for $(uname -r)"
  else
    info "new-lg4ff is not built for $(uname -r); the in-kernel hid-logitech driver still supports the native G29"
  fi

  mapfile -t wheels < <(find_wheels)
  if ((${#wheels[@]} == 0)); then
    info "no G29 connected; skipping device checks"
    return "$failures"
  fi
  for entry in "${wheels[@]}"; do
    read -r dir id <<<"$entry"
    if [[ $id == C260 ]]; then
      fail "${dir##*/} is still in PS4 mode (c260); see: journalctl -b | grep g29-ps4-modeswitch"
      continue
    fi
    ok "${dir##*/} is in native mode (c24f)"
    name=; [[ -L $dir/driver ]] && name=$(basename -- "$(readlink -f "$dir/driver")")
    [[ $name == logitech ]] && ok "bound to the logitech driver" || fail "bound to '${name:-nothing}', expected logitech"
    [[ -r $dir/range ]] && ok "rotation range $(<"$dir/range") degrees, gain $(<"$dir/gain"), autocenter $(<"$dir/autocenter")" \
      || fail "driver exposes no range attribute"
    for input in "$dir"/input/input*; do
      [[ -d $input ]] || continue
      ff=$(<"$input/capabilities/ff")
      [[ $ff != 0 ]] && ok "force feedback available ($(<"$input/name"))" || fail "no force-feedback capabilities"
      for name in "$input"/event*; do
        [[ -e $name ]] || continue
        name=/dev/input/${name##*/}
        [[ -r $name && -w $name ]] && ok "$name is readable and writable by $USER" \
          || fail "$name is not accessible by $USER (log in on a local seat)"
      done
    done
  done
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) die "unknown action '$action' (install|check|dry-run|uninstall)" ;;
esac
