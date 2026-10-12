#!/usr/bin/env bash
# USB handbrake posing as a Logitech F710 (046d:c219): install|check|dry-run|uninstall.
# install and uninstall use sudo and rebuild the boot image with limine-update;
# the change takes effect after a reboot. check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
quirk="usbhid.quirks=0x046d:0xc219:0x400000"
dropin_src="$component_dir/omarchy-gaming-handbrake.conf"
dropin_dst=${HANDBRAKE_DROPIN_DST:-/etc/limine-entry-tool.d/omarchy-gaming-handbrake.conf}
sysfs_root=${HANDBRAKE_SYSFS_ROOT:-/sys}
cmdline_file=${HANDBRAKE_CMDLINE:-/proc/cmdline}
limine_update=${HANDBRAKE_LIMINE_UPDATE:-limine-update}
sudo_cmd=${HANDBRAKE_SUDO-sudo}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR handbrake: %s\n' "$*" >&2; exit 1; }

dry_run() {
  say "Install Limine drop-in: $dropin_dst"
  say "Kernel option: $quirk"
  say "Rebuild boot image: sudo $limine_update (reboot required)"
}

install_component() {
  [[ -r $dropin_src ]] || die "drop-in is missing: $dropin_src"
  if [[ -r $dropin_dst ]] && cmp -s "$dropin_src" "$dropin_dst"; then
    say "Limine drop-in already installed"
  else
    $sudo_cmd install -Dm644 "$dropin_src" "$dropin_dst" || die "cannot install $dropin_dst"
    $sudo_cmd "$limine_update" || die "$limine_update failed; remove $dropin_dst and rerun it to roll back"
  fi
  grep -qw -- "$quirk" "$cmdline_file" || say "Reboot to apply $quirk, then run: $0 check"
}

uninstall_component() {
  [[ -e $dropin_dst ]] || { say "Limine drop-in is not installed"; return 0; }
  $sudo_cmd rm -f -- "$dropin_dst" || die "cannot remove $dropin_dst"
  $sudo_cmd "$limine_update" || die "$limine_update failed"
  say "Removed $dropin_dst. Reboot to return the handbrake to the Logitech driver."
}

check_component() {
  local failures=0 dir driver input event found=0
  ok() { printf 'OK   handbrake: %s\n' "$*"; }
  fail() { printf 'FAIL handbrake: %s\n' "$*"; failures=$((failures + 1)); }
  info() { printf 'INFO handbrake: %s\n' "$*"; }

  if [[ -r $dropin_dst ]] && cmp -s "$dropin_src" "$dropin_dst"; then
    ok "Limine drop-in installed"
  else
    fail "Limine drop-in missing or outdated: $dropin_dst"
  fi
  if grep -qw -- "$quirk" "$cmdline_file"; then
    ok "running kernel has $quirk"
  else
    fail "running kernel lacks $quirk (install, then reboot)"
  fi

  for dir in "$sysfs_root"/bus/hid/devices/0003:046D:C219.*; do
    [[ -d $dir ]] || continue
    found=1
    driver=; [[ -L $dir/driver ]] && driver=$(basename -- "$(readlink -f "$dir/driver")")
    if [[ $driver == hid-generic ]]; then
      ok "${dir##*/} is bound to hid-generic"
    else
      fail "${dir##*/} is bound to '${driver:-nothing}', expected hid-generic"
      continue
    fi
    for input in "$dir"/input/input*; do
      [[ -d $input ]] || continue
      ok "input device: $(<"$input/name")"
      for event in "$input"/event*; do
        [[ -e $event ]] || continue
        event=/dev/input/${event##*/}
        [[ -r $event ]] && ok "$event is readable by $USER" || fail "$event is not readable by $USER"
      done
    done
  done
  ((found)) || info "no 046d:c219 handbrake connected; skipping device checks"
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) die "unknown action '$action' (install|check|dry-run|uninstall)" ;;
esac
