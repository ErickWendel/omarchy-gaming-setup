#!/usr/bin/env bash
set -euo pipefail

# Install the managed game window rules (gaming.lua) and monitor layout
# (displays.lua) into ~/.config/hypr and load each from hyprland.lua with a
# single require line, plus the user service that gives fullscreen back to the
# previous window. Safe to rerun.
component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
hypr_dir="$HOME/.config/hypr"
config="$hypr_dir/hyprland.lua"

[[ -f $config ]] || { echo "Missing Hyprland config: $config" >&2; exit 2; }

# install_module <name> <comment>: copy <name>.lua and require it once.
install_module() {
  local name=$1 comment=$2 require_line="require(\"hypr.$1\")"
  install -Dm644 "$component_dir/$name.lua" "$hypr_dir/$name.lua"
  if ! grep -Fxq "$require_line" "$config"; then
    printf '\n-- %s managed by omarchy-gaming-setup.\n%s\n' "$comment" "$require_line" >> "$config"
    echo "Added $require_line to $config"
  fi
}
install_module gaming "Game window rules"
install_module displays "Monitor layout (DisplayPort monitor first)"

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors)
  [[ -z $errors ]] || { echo "Hyprland config errors: $errors" >&2; exit 1; }
fi
echo "Hyprland game rules and monitor layout installed: $hypr_dir/gaming.lua, $hypr_dir/displays.lua"

install -Dm755 "$component_dir/fullscreen-restore" "$HOME/.local/lib/omarchy-gaming-setup/fullscreen-restore"
install -Dm644 "$component_dir/fullscreen-restore.service" "$HOME/.config/systemd/user/fullscreen-restore.service"
systemctl --user daemon-reload
systemctl --user enable fullscreen-restore.service >/dev/null 2>&1
systemctl --user restart fullscreen-restore.service
echo "Fullscreen restore service running: fullscreen-restore.service"
