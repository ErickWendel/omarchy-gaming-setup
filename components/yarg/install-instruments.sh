#!/usr/bin/env bash
set -euo pipefail

# Lets the logged-in user read PS3 / Wii Guitar Hero and Rock Band
# instruments as raw HID, which YARG needs to recognise them (see the rule).
#   install-instruments.sh          install the udev rule (asks for sudo)
#   install-instruments.sh check    report whether connected instruments are readable

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rule_src="$component_dir/71-omarchy-yarg-instruments.rules"
rule_dst=${YARG_INSTRUMENTS_RULE_DST:-/etc/udev/rules.d/71-omarchy-yarg-instruments.rules}
sudo_cmd=${YARG_INSTRUMENTS_SUDO-sudo}

instrument_nodes() { # prints "/dev/hidrawN name"
  local dir id name
  for dir in /sys/class/hidraw/hidraw*; do
    [[ -e $dir/device/uevent ]] || continue
    id=$(sed -n 's/^HID_ID=//p' "$dir/device/uevent")
    [[ ${id^^} == *:000012BA:* || ${id^^} == *:00001BAD:* ]] || continue
    name=$(sed -n 's/^HID_NAME=//p' "$dir/device/uevent")
    printf '/dev/%s %s\n' "${dir##*/}" "$name"
  done
}

check() {
  local rc=0 node name found=0
  cmp -s "$rule_src" "$rule_dst" && echo "OK   $rule_dst installed" ||
    { echo "FAIL $rule_dst missing or outdated"; rc=1; }
  while read -r node name; do
    found=1
    [[ -r $node ]] && echo "OK   $node readable ($name)" ||
      { echo "FAIL $node not readable ($name)"; rc=1; }
  done < <(instrument_nodes)
  ((found)) || echo "INFO no PS3/Wii instrument connected"
  return "$rc"
}

if [[ ${1:-} == check ]]; then
  check
  exit
fi

$sudo_cmd install -Dm644 "$rule_src" "$rule_dst"
$sudo_cmd udevadm control --reload
$sudo_cmd udevadm trigger --action=change --subsystem-match=hidraw
$sudo_cmd udevadm settle --timeout=10 || true
echo "Installed $rule_dst"
check
