#!/usr/bin/env bash
# USB handbrake posing as a Logitech F710 (046d:c219): install|check|dry-run|uninstall.
# install and uninstall use sudo. The kernel quirk needs limine-update and a
# reboot; the bridge service and udev rule apply immediately.
# check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
quirk="usbhid.quirks=0x046d:0xc219:0x400000"
virtual_name="Omarchy USB Handbrake"
service=omarchy-handbrake-bridge.service
dropin_src="$component_dir/omarchy-gaming-handbrake.conf"
dropin_dst=${HANDBRAKE_DROPIN_DST:-/etc/limine-entry-tool.d/omarchy-gaming-handbrake.conf}
rule_src="$component_dir/72-omarchy-handbrake-hide.rules"
rule_dst=${HANDBRAKE_RULE_DST:-/etc/udev/rules.d/72-omarchy-handbrake-hide.rules}
bridge_src="$component_dir/omarchy-handbrake-bridge"
bridge_dst=${HANDBRAKE_BRIDGE_DST:-/usr/local/lib/omarchy-gaming-setup/omarchy-handbrake-bridge}
unit_src="$component_dir/$service"
unit_dst=${HANDBRAKE_UNIT_DST:-/etc/systemd/system/$service}
# Superseded by the bridge; removed on install.
legacy_rule=${HANDBRAKE_LEGACY_RULE:-/etc/udev/rules.d/70-omarchy-handbrake-hidraw.rules}
sysfs_root=${HANDBRAKE_SYSFS_ROOT:-/sys}
dev_root=${HANDBRAKE_DEV_ROOT:-/dev}
cmdline_file=${HANDBRAKE_CMDLINE:-/proc/cmdline}
limine_update=${HANDBRAKE_LIMINE_UPDATE:-limine-update}
sudo_cmd=${HANDBRAKE_SUDO-sudo}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR handbrake: %s\n' "$*" >&2; exit 1; }
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }

dry_run() {
  say "Install Limine drop-in: $dropin_dst"
  say "Kernel option: $quirk"
  say "Rebuild boot image: sudo $limine_update (reboot required)"
  say "Install bridge: $bridge_dst and $unit_dst (enabled now)"
  say "Hide the raw handbrake from user sessions: $rule_dst"
  [[ ! -e $legacy_rule ]] || say "Remove superseded rule: $legacy_rule"
}

# Print the raw event/js/hidraw device nodes of every connected handbrake.
raw_nodes() {
  local dir node
  for dir in "$sysfs_root"/bus/hid/devices/0003:046D:C219.*; do
    for node in "$dir"/input/input*/event* "$dir"/input/input*/js* "$dir"/hidraw/hidraw*; do
      [[ -e $node ]] || continue
      [[ $node == */hidraw/* ]] && node=$dev_root/${node##*/} || node=$dev_root/input/${node##*/}
      [[ -e $node ]] && printf '%s\n' "$node"
    done
  done
}

# Re-apply the rules to connected handbrakes. A change event does not revoke
# session ACLs granted earlier, so clear them; udev re-adds them only if tagged.
reload_udev() {
  local dir node
  $sudo_cmd udevadm control --reload || die "udev rules reload failed"
  for dir in "$sysfs_root"/bus/hid/devices/0003:046D:C219.*; do
    [[ -e $dir ]] || continue
    $sudo_cmd udevadm trigger --action=change --parent-match="$(readlink -f "$dir")" || die "udev trigger failed"
  done
  $sudo_cmd udevadm settle --timeout=10 || true
  while read -r node; do
    $sudo_cmd setfacl -b -- "$node" || die "cannot clear ACLs on $node"
    $sudo_cmd udevadm trigger --action=change --name-match="$node" || die "udev trigger failed"
  done < <(raw_nodes)
  $sudo_cmd udevadm settle --timeout=10 || true
}

install_component() {
  local file
  for file in "$dropin_src" "$rule_src" "$bridge_src" "$unit_src"; do
    [[ -r $file ]] || die "component file is missing: $file"
  done
  python3 -I -c 'import evdev' 2>/dev/null || die "python-evdev is required (pacman -S python-evdev)"

  local udev_changed=0
  if [[ -e $legacy_rule ]]; then
    $sudo_cmd rm -f -- "$legacy_rule" || die "cannot remove $legacy_rule"
    say "Removed superseded $legacy_rule"
    udev_changed=1
  fi
  if ! same "$rule_src" "$rule_dst"; then
    $sudo_cmd install -Dm644 "$rule_src" "$rule_dst" || die "cannot install $rule_dst"
    udev_changed=1
  fi
  local node
  while read -r node; do
    [[ -r $node ]] && udev_changed=1
  done < <(raw_nodes)
  ((udev_changed)) && reload_udev

  if ! same "$bridge_src" "$bridge_dst" || ! same "$unit_src" "$unit_dst"; then
    $sudo_cmd install -Dm755 "$bridge_src" "$bridge_dst" || die "cannot install $bridge_dst"
    $sudo_cmd install -Dm644 "$unit_src" "$unit_dst" || die "cannot install $unit_dst"
    $sudo_cmd systemctl daemon-reload || die "systemctl daemon-reload failed"
    $sudo_cmd systemctl enable "$service" || die "cannot enable $service"
    $sudo_cmd systemctl restart "$service" || die "cannot start $service"
  fi

  if same "$dropin_src" "$dropin_dst"; then
    say "Limine drop-in already installed"
  else
    $sudo_cmd install -Dm644 "$dropin_src" "$dropin_dst" || die "cannot install $dropin_dst"
    $sudo_cmd "$limine_update" || die "$limine_update failed; remove $dropin_dst and rerun it to roll back"
  fi
  grep -qw -- "$quirk" "$cmdline_file" || say "Reboot to apply $quirk, then run: $0 check"
}

uninstall_component() {
  if [[ -e $unit_dst ]]; then
    $sudo_cmd systemctl disable --now "$service" || die "cannot stop $service"
    $sudo_cmd rm -f -- "$unit_dst" "$bridge_dst" || die "cannot remove the bridge"
    $sudo_cmd systemctl daemon-reload || die "systemctl daemon-reload failed"
    say "Removed $service"
  fi
  if [[ -e $rule_dst ]]; then
    $sudo_cmd rm -f -- "$rule_dst" || die "cannot remove $rule_dst"
    reload_udev
    say "Removed $rule_dst"
  fi
  [[ -e $dropin_dst ]] || { say "Limine drop-in is not installed"; return 0; }
  $sudo_cmd rm -f -- "$dropin_dst" || die "cannot remove $dropin_dst"
  $sudo_cmd "$limine_update" || die "$limine_update failed"
  say "Removed $dropin_dst. Reboot to return the handbrake to the Logitech driver."
}

check_component() {
  local failures=0 dir driver node input found=0 virtual=
  ok() { printf 'OK   handbrake: %s\n' "$*"; }
  fail() { printf 'FAIL handbrake: %s\n' "$*"; failures=$((failures + 1)); }
  info() { printf 'INFO handbrake: %s\n' "$*"; }

  same "$dropin_src" "$dropin_dst" && ok "Limine drop-in installed" \
    || fail "Limine drop-in missing or outdated: $dropin_dst"
  same "$rule_src" "$rule_dst" && ok "hide rule installed" || fail "hide rule missing or outdated: $rule_dst"
  [[ ! -e $legacy_rule ]] || fail "superseded rule still installed: $legacy_rule"
  same "$bridge_src" "$bridge_dst" && same "$unit_src" "$unit_dst" && ok "bridge installed" \
    || fail "bridge missing or outdated: $bridge_dst, $unit_dst"
  if systemctl is-active --quiet "$service"; then
    ok "$service is active"
  else
    fail "$service is not active (journalctl -u $service)"
  fi
  grep -qw -- "$quirk" "$cmdline_file" && ok "running kernel has $quirk" \
    || fail "running kernel lacks $quirk (install, then reboot)"

  for dir in "$sysfs_root"/bus/hid/devices/0003:046D:C219.*; do
    [[ -d $dir ]] || continue
    found=1
    driver=; [[ -L $dir/driver ]] && driver=$(basename -- "$(readlink -f "$dir/driver")")
    if [[ $driver == hid-generic ]]; then
      ok "${dir##*/} is bound to hid-generic"
    else
      fail "${dir##*/} is bound to '${driver:-nothing}', expected hid-generic"
    fi
  done
  while read -r node; do
    [[ -r $node ]] && fail "raw $node is still visible to $USER; rerun install or replug the handbrake" \
      || ok "raw $node is hidden from $USER"
  done < <(raw_nodes)
  ((found)) || info "no 046d:c219 handbrake connected"

  for input in "$sysfs_root"/class/input/input*; do
    [[ -r $input/name && $(<"$input/name") == "$virtual_name" ]] || continue
    for node in "$input"/event*; do
      [[ -e $node ]] || continue
      virtual=$dev_root/input/${node##*/}
    done
  done
  if [[ -z $virtual ]]; then
    fail "virtual \"$virtual_name\" joystick not present"
  elif [[ -r $virtual ]]; then
    ok "virtual \"$virtual_name\" joystick is $virtual"
  else
    fail "virtual $virtual is not readable by $USER"
  fi
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) die "unknown action '$action' (install|check|dry-run|uninstall)" ;;
esac
