#!/usr/bin/env bash
set -euo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_dir="$HOME/.local/bin"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"

install -Dm755 "$component_dir/pcsx2-launch" "$bin_dir/omarchy-pcsx2"

mapfile -t shortcuts_files < <(find "$steam_root/userdata" -mindepth 3 -maxdepth 3 \
  -path '*/config/shortcuts.vdf' -type f -print 2>/dev/null)
if ((${#shortcuts_files[@]} == 0)); then
  echo "No Steam shortcuts.vdf found; installed wrapper only."
  exit 0
fi
if ((${#shortcuts_files[@]} > 1)); then
  echo "Multiple Steam users have shortcuts; set STEAM_USER_ID explicitly." >&2
  exit 2
fi

shortcuts=${shortcuts_files[0]}
config_dir=${shortcuts%/shortcuts.vdf}
exec python "$component_dir/configure_steam_shortcuts.py" \
  --shortcuts "$shortcuts" \
  --localconfig "$config_dir/localconfig.vdf" \
  --wrapper "$bin_dir/omarchy-pcsx2"

