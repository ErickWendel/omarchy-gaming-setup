#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
fake_pid=
trap '[[ -z $fake_pid ]] || kill "$fake_pid" 2>/dev/null; rm -rf -- "$test_root"' EXIT
test_home="$test_root/home"
fake_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"
install_dir="$test_home/.local/opt/delta-center"
autostart="$test_home/.config/autostart"
desktop="$test_home/.local/share/applications/delta-center.desktop"
unit="$test_home/.config/systemd/user/delta-center.service"
backups="$test_home/backups"
mkdir -p "$autostart" "$fake_bin" "$(dirname -- "$desktop")"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "$*" >>"$SYSTEMCTL_LOG"' \
  'if [[ ${1:-} == --user && ${2:-} == is-active && ${4:-} == graphical-session.target && ${GRAPHICAL_ACTIVE:-0} != 1 ]]; then exit 1; fi' \
  'if [[ ${1:-} == --user && ${2:-} == enable ]]; then mkdir -p "$HOME/.config/systemd/user/graphical-session.target.wants"; ln -sf ../delta-center.service "$HOME/.config/systemd/user/graphical-session.target.wants/delta-center.service"; fi' \
  'if [[ ${1:-} == --user && ${2:-} == show ]]; then echo "${FAKE_MAIN_PID:-0}"; fi' \
  'exit 0' >"$fake_bin/systemctl"
chmod +x "$fake_bin/systemctl"

export HOME="$test_home"
export PATH="$fake_bin:$PATH"
export SYSTEMCTL_LOG="$systemctl_log"
export OMARCHY_BACKUP_ROOT="$backups"
unset DISPLAY WAYLAND_DISPLAY

# A missing runtime fails with remediation and changes nothing.
legacy_entry=$(printf '%s\n' '[Desktop Entry]' 'Type=Application' "Exec=$install_dir/delta-center-launch")
printf '%s\n' "$legacy_entry" >"$autostart/delta-center.desktop"
if "$repo_dir/scripts/delta.sh" install 2>"$test_root/err"; then
  echo 'install must fail without a runtime' >&2; exit 1
fi
grep -q -- '--delta-archive' "$test_root/err"
test -e "$autostart/delta-center.desktop"
test ! -e "$unit"
! grep -q 'enable' "$systemctl_log" 2>/dev/null

# Install from a local archive. The fake binary is sleep so its argv[0] is the
# runtime path, like the real Electron main process.
mkdir -p "$test_root/archive/delta-center-linux-compat-x64"
cp "$(command -v sleep)" "$test_root/archive/delta-center-linux-compat-x64/delta-center"
tar -czf "$test_root/delta.tar.gz" -C "$test_root/archive" .
# Earlier releases renamed the entry in place, which still autostarted.
printf '%s\n' "$legacy_entry" >"$autostart/delta-center.desktop.disabled-by-omarchy-gaming-setup"
printf '%s\n' '[Desktop Entry]' 'Exec=/usr/bin/unrelated' >"$autostart/other.desktop"

"$repo_dir/setup.sh" --delta-archive "$test_root/delta.tar.gz" --dry-run | grep >/dev/null 'Install Delta runtime from archive'
"$repo_dir/scripts/delta.sh" install --archive "$test_root/delta.tar.gz"
"$repo_dir/scripts/delta.sh" install --archive "$test_root/delta.tar.gz" | grep >/dev/null 'already installed from this archive'
"$repo_dir/scripts/delta.sh" install

test -x "$install_dir/delta-center-launch"
grep -q -- '--ozone-platform=x11' "$install_dir/delta-center-launch"
grep -q '^ExecStart=%h/.local/opt/delta-center/delta-center-launch --hidden$' "$unit"
grep -q '^PartOf=graphical-session.target$' "$unit"
grep -q '^WantedBy=graphical-session.target$' "$unit"
grep -q '^Restart=on-failure$' "$unit"
test "$(ls -A "$autostart")" = other.desktop
test -e "$backups/.config/autostart/delta-center.desktop"
test -e "$backups/.config/autostart/delta-center.desktop.disabled-by-omarchy-gaming-setup"
test "$(find "$backups" -type f | wc -l)" -eq 2
test -z "$(find "$test_home/.local/opt" -maxdepth 1 -name 'delta-center.new.*')"
grep -qx "Exec=$install_dir/delta-center-launch" "$desktop"
test "$(grep -c '^--user enable delta-center.service$' "$systemctl_log")" -eq 3
! grep -q '^--user restart' "$systemctl_log"

# An existing menu launcher and launcher script are preserved.
printf '%s\n' '[Desktop Entry]' 'Name=Custom' "Exec=$install_dir/delta-center-launch" >"$desktop"
cp "$desktop" "$test_root/desktop.before"
"$repo_dir/scripts/delta.sh" install >/dev/null
cmp -s "$desktop" "$test_root/desktop.before"

# In a graphical session the service is (re)started and unmanaged instances stop.
"$install_dir/delta-center" 300 &
stray_pid=$!
export DISPLAY=:0 GRAPHICAL_ACTIVE=1
"$repo_dir/scripts/delta.sh" install | grep >/dev/null 'Stopped unmanaged Delta Center instance'
! kill -0 "$stray_pid" 2>/dev/null
grep -q '^--user restart delta-center.service$' "$systemctl_log"

# Check passes with one hidden managed instance and flags a duplicate.
exec -a "$install_dir/delta-center" bash -c 'sleep 300; :' launch --hidden &
fake_pid=$!
export FAKE_MAIN_PID=$fake_pid
"$repo_dir/scripts/delta.sh" check >"$test_root/check"
grep -q 'OK   Delta: running service command includes --hidden' "$test_root/check"
printf '%s\n' "$legacy_entry" >"$autostart/delta-center.desktop.disabled-by-omarchy-gaming-setup"
if "$repo_dir/scripts/delta.sh" check >"$test_root/check"; then
  echo 'check must flag a leftover autostart entry' >&2; exit 1
fi
grep -q 'WARN Delta: no XDG autostart entry launches Delta' "$test_root/check"

echo 'Delta install/check/dry-run/idempotency test passed'
