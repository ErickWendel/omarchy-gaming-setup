#!/usr/bin/env bash
# Logitech G923 Xbox edition on logitech-trueforce-dkms: install|check|dry-run|uninstall.
# install and uninstall use sudo for the hid-logitech-dd options and to remove
# the Xbox-mode rule this component used to install; check and dry-run never
# change the system or send anything to the wheel.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
sysfs_root=${G923_SYSFS_ROOT:-/sys}
options_src="$component_dir/logitech-trueforce.conf"
options_dst=${G923_OPTIONS_DST:-/etc/modprobe.d/logitech-trueforce.conf}
# Installed by earlier versions of this component; the package's rule replaces them.
legacy_config=${G923_CONFIG_DST:-/etc/usb_modeswitch.d/046d:c26d}
legacy_rule=${G923_RULE_DST:-/etc/udev/rules.d/41-omarchy-g923-xbox-mode.rules}
# From logitech-trueforce-dkms: the udev rule that switches c26d to PC mode
# through logi-wheel-modeswitch, which calls usb_modeswitch.
package_rule=${G923_PACKAGE_RULE:-/usr/lib/udev/rules.d/73-logitech-xbox-modeswitch.rules}
package_modeswitch=${G923_PACKAGE_MODESWITCH:-/usr/bin/logi-wheel-modeswitch}
usb_modeswitch=${G923_USB_MODESWITCH:-/usr/bin/usb_modeswitch}
# Also from the package: lists hid-logitech-dd for mkinitcpio and regenerates
# the image, which also carries /etc/modprobe.d (modconf hook).
initramfs_tool=${G923_INITRAMFS_TOOL:-/usr/bin/logi-wheel-initramfs}
backup_root=${OMARCHY_BACKUP_ROOT:-$HOME/.local/state/omarchy-gaming-setup/backups}
sudo_cmd=${G923_SUDO-sudo}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR G923: %s\n' "$*" >&2; exit 1; }

# Print the USB device directory of every G923 Xbox edition still in Xbox mode.
# In that mode it is a vendor-class device, so it has no HID node yet.
find_xbox_mode() {
  local dir
  for dir in "$sysfs_root"/bus/usb/devices/*; do
    [[ -r $dir/idVendor && -r $dir/idProduct ]] || continue
    [[ $(<"$dir/idVendor") == 046d && $(<"$dir/idProduct") == c26d ]] && printf '%s\n' "$dir"
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

# Put a managed file back the way it was before install: the backed-up copy,
# or nothing.
restore_system_file() {
  local path=$1 backup="$backup_root/system$1"
  if [[ -e $backup ]]; then
    $sudo_cmd install -Dm"$(stat -c %a "$backup")" "$backup" "$path" || die "cannot restore $path"
    rm -f -- "$backup"
    say "Restored $path from $backup"
  elif [[ -e $path ]]; then
    $sudo_cmd rm -f -- "$path" || die "cannot remove $path"
    say "Removed $path"
  fi
  rm -f -- "$backup.absent"
}

# Earlier versions installed their own usb_modeswitch config and udev rule;
# they would switch the wheel a second time beside the package's rule.
remove_legacy() {
  local path
  for path in "$legacy_rule" "$legacy_config"; do
    [[ -e $path || -e $backup_root/system$path || -e $backup_root/system$path.absent ]] || continue
    restore_system_file "$path"
  done
}

# The options load from the initramfs at boot, so a changed file needs a new image.
refresh_initramfs() {
  if [[ -x $initramfs_tool ]]; then
    $sudo_cmd "$initramfs_tool" --force || die "initramfs regeneration failed"
  else
    say "logitech-trueforce-dkms is not installed; the options apply once it is"
  fi
}

dry_run() {
  say "Remove this component's old Xbox-mode rule and usb_modeswitch config, if installed: $legacy_rule $legacy_config"
  say "Install hid-logitech-dd options: $options_dst (regenerates the initramfs when changed)"
  say "Reload udev rules and switch any G923 currently in Xbox mode with the package's rule: $package_rule"
  say "Backups: $backup_root/system"
}

install_component() {
  [[ -r $options_src ]] || die "component files are missing in $component_dir"
  [[ -x $usb_modeswitch ]] || die "usb_modeswitch is not installed (scripts/packages.sh install adds it)"
  [[ -r $package_rule && -x $package_modeswitch ]] \
    || die "logitech-trueforce-dkms is not installed (scripts/packages.sh install adds it)"
  remove_legacy
  backup_system_file "$options_dst"
  if ! cmp -s "$options_src" "$options_dst" 2>/dev/null; then
    $sudo_cmd install -Dm644 "$options_src" "$options_dst" || die "cannot install $options_dst"
    refresh_initramfs
    say "Unplug the wheel, then run: sudo modprobe -r hid-logitech-dd && sudo modprobe hid-logitech-dd"
  fi
  $sudo_cmd udevadm control --reload || die "udev rules reload failed"
  local dir
  while read -r dir; do
    say "Switching connected G923 (${dir##*/}) from Xbox mode to PC mode"
    $sudo_cmd udevadm trigger --action=add "$dir"
  done < <(find_xbox_mode)
  $sudo_cmd udevadm settle --timeout=10 || true
  say "G923 support installed. Run: $0 check"
}

uninstall_component() {
  remove_legacy
  restore_system_file "$options_dst"
  $sudo_cmd udevadm control --reload || die "udev rules reload failed"
  refresh_initramfs
  say "Uninstalled. logitech-trueforce-dkms stays installed and keeps switching the wheel to PC mode;"
  say "removing it leaves the wheel in Xbox mode, where Linux cannot use it."
}

check_component() {
  local failures=0 dir input name ff engine path found=0
  ok() { printf 'OK   G923: %s\n' "$*"; }
  fail() { printf 'FAIL G923: %s\n' "$*"; failures=$((failures + 1)); }
  info() { printf 'INFO G923: %s\n' "$*"; }

  [[ -x $usb_modeswitch ]] && ok "usb_modeswitch installed" || fail "usb_modeswitch is not installed"
  if [[ -r $package_rule && -x $package_modeswitch ]]; then
    ok "Xbox-mode switch installed by logitech-trueforce-dkms"
  else
    fail "logitech-trueforce-dkms Xbox-mode switch missing: $package_rule"
  fi
  for path in "$legacy_rule" "$legacy_config"; do
    [[ -e $path ]] && fail "old Xbox-mode file still installed: $path (run: $0 install)"
  done
  if cmp -s "$options_src" "$options_dst" 2>/dev/null; then
    ok "hid-logitech-dd options installed"
  else
    fail "hid-logitech-dd options missing or outdated: $options_dst"
  fi

  while read -r dir; do
    found=1
    fail "${dir##*/} is still in Xbox mode (c26d); see: journalctl -b -t logi-wheel-modeswitch"
  done < <(find_xbox_mode)
  # Interface 0 carries the wheel; interface 1 is a second HID++ node with no input.
  for dir in "$sysfs_root"/bus/hid/devices/0003:046D:C26E.*; do
    [[ -d $dir && $(<"$dir/../bInterfaceNumber") == 00 ]] 2>/dev/null || continue
    found=1
    ok "${dir##*/} is in PC mode (c26e)"
    name=; [[ -L $dir/driver ]] && name=$(basename -- "$(readlink -f "$dir/driver")")
    [[ $name == logitech-dd ]] && ok "bound to the logitech-dd driver (logitech-trueforce-dkms)" \
      || fail "bound to '${name:-nothing}', expected logitech-dd (install logitech-trueforce-dkms, then replug)"
    engine=$(cat "$sysfs_root/module/hid_logitech_dd/parameters/g923_xbox_dd_engine" 2>/dev/null)
    [[ $engine == Y ]] && ok "driver force engine on (g923_xbox_dd_engine=1)" \
      || fail "driver force engine off; unplug the wheel and reload hid-logitech-dd"
    [[ -r $dir/range ]] && ok "rotation range $(<"$dir/range") degrees" || fail "driver exposes no range attribute"
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
  ((found)) || info "no G923 connected; skipping device checks"
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) die "unknown action '$action' (install|check|dry-run|uninstall)" ;;
esac
