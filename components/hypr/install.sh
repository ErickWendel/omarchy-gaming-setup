#!/usr/bin/env bash
set -euo pipefail

# Install the managed game window rules as ~/.config/hypr/gaming.lua and load
# them from hyprland.lua with a single require line, plus the user service
# that gives fullscreen back to the previous window. Safe to rerun.
component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
hypr_dir="$HOME/.config/hypr"
config="$hypr_dir/hyprland.lua"
require_line='require("hypr.gaming")'

[[ -f $config ]] || { echo "Missing Hyprland config: $config" >&2; exit 2; }
install -Dm644 "$component_dir/gaming.lua" "$hypr_dir/gaming.lua"

if ! grep -Fxq "$require_line" "$config"; then
  printf '\n-- Game window rules managed by omarchy-gaming-setup.\n%s\n' "$require_line" >> "$config"
  echo "Added $require_line to $config"
fi

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors)
  [[ -z $errors ]] || { echo "Hyprland config errors: $errors" >&2; exit 1; }
fi
echo "Hyprland game rules installed: $hypr_dir/gaming.lua"

install -Dm755 "$component_dir/fullscreen-restore" "$HOME/.local/lib/omarchy-gaming-setup/fullscreen-restore"
install -Dm644 "$component_dir/fullscreen-restore.service" "$HOME/.config/systemd/user/fullscreen-restore.service"
systemctl --user daemon-reload
systemctl --user enable fullscreen-restore.service >/dev/null 2>&1
systemctl --user restart fullscreen-restore.service
echo "Fullscreen restore service running: fullscreen-restore.service"
