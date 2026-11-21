#!/usr/bin/env bash
set -euo pipefail

# Installs omarchy-yarg, a "YARG" entry in the app menu, and a "YARG"
# non-Steam shortcut that runs it, so the Steam guest (which shares this
# Steam) can start YARG from Big Picture.
#   install.sh          install launcher + shortcut (Steam must be closed)
#   install.sh check    report what is in place

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_dir="$HOME/.local/bin"
launcher="$bin_dir/omarchy-yarg"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-gaming-setup/backups"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
desktop_file="$data_home/applications/yarg.desktop"
menu_icon="$data_home/icons/hicolor/256x256/apps/omarchy-yarg.png"

shortcuts_file() {
  find "$steam_root/userdata" -mindepth 3 -maxdepth 3 \
    -path "*/userdata/${STEAM_USER_ID:-*}/config/shortcuts.vdf" -type f -print 2>/dev/null | head -1
}

check() {
  local rc=0 yarg shortcuts
  [[ -x $launcher ]] && cmp -s "$component_dir/yarg-launch" "$launcher" &&
    echo "OK   $launcher installed" || { echo "FAIL $launcher missing or outdated"; rc=1; }
  cmp -s "$component_dir/webm-videos.py" "$bin_dir/omarchy-yarg-videos" &&
    echo "OK   $bin_dir/omarchy-yarg-videos installed" || { echo "FAIL $bin_dir/omarchy-yarg-videos missing or outdated"; rc=1; }
  cmp -s "$component_dir/windows-names.py" "$bin_dir/omarchy-yarg-windows-names" &&
    echo "OK   $bin_dir/omarchy-yarg-windows-names installed" || { echo "FAIL $bin_dir/omarchy-yarg-windows-names missing or outdated"; rc=1; }
  cmp -s "$component_dir/game-playlists.py" "$bin_dir/omarchy-yarg-playlists" &&
    echo "OK   $bin_dir/omarchy-yarg-playlists installed" || { echo "FAIL $bin_dir/omarchy-yarg-playlists missing or outdated"; rc=1; }
  [[ -f $desktop_file ]] && grep -qx "Exec=$launcher" "$desktop_file" &&
    echo "OK   app menu entry $desktop_file" || { echo "FAIL no app menu entry for $launcher"; rc=1; }
  "$component_dir/install-windows.sh" check || rc=1
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
install -Dm755 "$component_dir/webm-videos.py" "$bin_dir/omarchy-yarg-videos"
install -Dm755 "$component_dir/windows-names.py" "$bin_dir/omarchy-yarg-windows-names"
install -Dm755 "$component_dir/game-playlists.py" "$bin_dir/omarchy-yarg-playlists"
echo "Installed $launcher"

# App menu entry, with the Steam shortcut's artwork as its icon when there is one.
shortcuts=$(shortcuts_file)
if [[ -n $shortcuts ]]; then
  appid=$(python3 -I "$component_dir/configure_steam.py" --print-appid \
    --shortcuts "$shortcuts" --exe "$launcher" --backup-dir "$backup_dir" 2>/dev/null || true)
  icon_src="${shortcuts%/shortcuts.vdf}/grid/${appid}_icon.png"
  [[ -n $appid && -f $icon_src ]] && install -Dm644 "$icon_src" "$menu_icon"
fi
mkdir -p -- "$(dirname -- "$desktop_file")"
cat >"$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=YARG
GenericName=Rhythm Game
Comment=Yet Another Rhythm Game: guitar, drums and vocals
Exec=$launcher
Icon=$([[ -f $menu_icon ]] && echo "$menu_icon" || echo applications-games)
Categories=Game;
Keywords=guitar;hero;rock;band;clone;rhythm;
Terminal=false
DESKTOP
echo "Installed app menu entry $desktop_file"
"$component_dir/install-windows.sh"

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
