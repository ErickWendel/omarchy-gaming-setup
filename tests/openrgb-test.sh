#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
test_home="$test_root/home"
fake_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"
openrgb_log="$test_root/openrgb.log"
mkdir -p "$test_home/.config/autostart" "$fake_bin"

printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Exec=/usr/bin/openrgb --startminimized' >"$test_home/.config/autostart/OpenRGB.desktop"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "$*" >>"$SYSTEMCTL_LOG"' \
  'if [[ ${1:-} == --user && ${2:-} == is-active && ${4:-} == graphical-session.target && ${GRAPHICAL_ACTIVE:-0} != 1 ]]; then exit 1; fi' \
  'exit 0' >"$fake_bin/systemctl"
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' "$*" >>"$OPENRGB_LOG"' 'exit 0' >"$fake_bin/openrgb"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ ${PGREP_HAS_PROCESS:-0} == 1 ]]; then echo 1234; exit 0; fi' \
  'exit 1' >"$fake_bin/pgrep"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/pkill"
chmod +x "$fake_bin/systemctl" "$fake_bin/openrgb" "$fake_bin/pgrep" "$fake_bin/pkill"

export HOME="$test_home"
export PATH="$fake_bin:$PATH"
export SYSTEMCTL_LOG="$systemctl_log"
export OPENRGB_LOG="$openrgb_log"
export OPENRGB_BIN="$fake_bin/openrgb"
export OMARCHY_BACKUP_ROOT="$test_home/backups"
unset DISPLAY WAYLAND_DISPLAY

"$repo_dir/scripts/openrgb.sh" dry-run | grep -q 'Install profile:'
"$repo_dir/scripts/openrgb.sh" install
"$repo_dir/scripts/openrgb.sh" install

profile="$test_home/.config/OpenRGB/static-green.orp"
unit="$test_home/.config/systemd/user/openrgb.service"
legacy="$test_home/.config/autostart/OpenRGB.desktop"
backup="$test_home/backups/.config/autostart/OpenRGB.desktop"

test -s "$profile"
grep -a -q '^OPENRGB_PROFILE' "$profile"
grep -q 'PartOf=graphical-session.target' "$unit"
grep -q 'ExecStart=/usr/bin/openrgb --startminimized --profile %h/.config/OpenRGB/static-green.orp' "$unit"
grep -q 'StartLimitBurst=3' "$unit"
test ! -e "$legacy"
test -e "$legacy.disabled-by-omarchy-gaming-setup"
test -e "$backup"
test "$(grep -c '^--autostart-disable$' "$openrgb_log")" -eq 2
test "$(grep -c '^--user enable openrgb.service$' "$systemctl_log")" -eq 2

export DISPLAY=:0
export GRAPHICAL_ACTIVE=1
export PGREP_HAS_PROCESS=0
"$repo_dir/scripts/openrgb.sh" install
grep -q '^--user restart openrgb.service$' "$systemctl_log"

export PGREP_HAS_PROCESS=1
"$repo_dir/scripts/openrgb.sh" check >/dev/null

if rg -i 'i2c|smbus' "$repo_dir/scripts/openrgb.sh" "$repo_dir/systemd/user/openrgb.service"; then
  echo 'Unsafe bus operation reference found in executable configuration' >&2
  exit 1
fi

echo 'OpenRGB install/dry-run/idempotency test passed'
