#!/usr/bin/env bash
set -euo pipefail

# Installs omarchy-yarg and a "YARG" non-Steam shortcut that runs it, so the
# Steam guest (which shares this Steam) can start YARG from Big Picture.
#   install.sh          install launcher + shortcut (Steam must be closed)
#   install.sh check    report what is in place

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_dir="$HOME/.local/bin"
launcher="$bin_dir/omarchy-yarg"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-gaming-setup/backups"

shortcuts_file() {
  find "$steam_root/userdata" -mindepth 3 -maxdepth 3 \
    -path "*/userdata/${STEAM_USER_ID:-*}/config/shortcuts.vdf" -type f -print 2>/dev/null | head -1
}

check() {
  local rc=0 yarg shortcuts
  [[ -x $launcher ]] && cmp -s "$component_dir/yarg-launch" "$launcher" &&
    echo "OK   $launcher installed" || { echo "FAIL $launcher missing or outdated"; rc=1; }
  yarg=$("$component_dir/yarg-launch" --print-yarg || true)
  [[ -n $yarg ]] && echo "OK   YARG install: $yarg" || { echo "FAIL no YARG install found"; rc=1; }
  shortcuts=$(shortcuts_file)
  if [[ -n $shortcuts ]] && python3 -I "$component_dir/configure_steam.py" --check \
      --shortcuts "$shortcuts" --exe "$launcher" --backup-dir "$backup_dir"; then
    echo "OK   Steam shortcut YARG runs $launcher"
  else
    echo "FAIL no Steam shortcut for $launcher"; rc=1
  fi
  return "$rc"
}

if [[ ${1:-} == check ]]; then
  check
  exit
fi

install -Dm755 "$component_dir/yarg-launch" "$launcher"
echo "Installed $launcher"

shortcuts=$(shortcuts_file)
if [[ -z $shortcuts ]]; then
  echo "No Steam shortcuts.vdf under $steam_root/userdata; installed the launcher only." >&2
  exit 1
fi
if pgrep -u "$(id -u)" -x steam >/dev/null || pgrep -u "$(id -u)" -f '/steamrt64/steam( |$)' >/dev/null; then
  echo "Steam is running and would overwrite shortcuts.vdf on exit. Close Steam and rerun." >&2
  exit 1
fi
# Artwork (cover, capsule, hero, logo, icon) lives in grid/<appid>*; Steam
# shows a non-Steam shortcut's icon only when its icon field names the file.
appid=$(python3 -I "$component_dir/configure_steam.py" --print-appid \
  --shortcuts "$shortcuts" --exe "$launcher" --backup-dir "$backup_dir")
icon="${shortcuts%/shortcuts.vdf}/grid/${appid}_icon.png"
[[ -f $icon ]] || icon=
python3 -I "$component_dir/configure_steam.py" \
  --shortcuts "$shortcuts" --exe "$launcher" --backup-dir "$backup_dir" ${icon:+--icon "$icon"}
