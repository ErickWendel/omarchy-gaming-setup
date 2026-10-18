#!/usr/bin/env bash
set -euo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_dir="$HOME/.local/bin"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"

install -Dm755 "$component_dir/pcsx2-launch" "$bin_dir/omarchy-pcsx2"
# A fresh install has no PCSX2.ini until PCSX2 runs once; still migrate the
# shortcuts and report the skipped settings through the exit status.
ini_status=0
python "$component_dir/configure_pcsx2_ini.py" || ini_status=$?

mapfile -t shortcuts_files < <(find "$steam_root/userdata" -mindepth 3 -maxdepth 3 \
  -path "*/userdata/${STEAM_USER_ID:-*}/config/shortcuts.vdf" -type f -print 2>/dev/null)
if ((${#shortcuts_files[@]} == 0)); then
  echo "No Steam shortcuts.vdf found; installed wrapper only."
  exit "$ini_status"
fi
if ((${#shortcuts_files[@]} > 1)); then
  echo "Multiple Steam users have shortcuts; set STEAM_USER_ID explicitly." >&2
  exit 2
fi

shortcuts=${shortcuts_files[0]}
config_dir=${shortcuts%/shortcuts.vdf}
python "$component_dir/configure_steam_shortcuts.py" \
  --shortcuts "$shortcuts" \
  --localconfig "$config_dir/localconfig.vdf" \
  --wrapper "$bin_dir/omarchy-pcsx2"
exit "$ini_status"

