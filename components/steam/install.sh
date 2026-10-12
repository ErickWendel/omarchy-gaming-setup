#!/usr/bin/env bash
set -euo pipefail

# Steam starts at login from its own "Run Steam when my computer starts"
# setting (~/.config/autostart/steam.desktop). An extra Hyprland launch only
# forwards to that instance, so remove it to keep a single startup path.
autostart="$HOME/.config/hypr/autostart.lua"

if [[ -f $autostart ]] && grep -Eq '^[[:space:]]*o\.launch_on_start\("steam( [^"]*)?"\)' "$autostart"; then
  sed -Ei '/^[[:space:]]*o\.launch_on_start\("steam( [^"]*)?"\)/d' "$autostart"
  echo "Removed the duplicate Steam launch from $autostart"
  if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null
    errors=$(hyprctl configerrors)
    [[ -z $errors ]] || { echo "Hyprland config errors: $errors" >&2; exit 1; }
  fi
else
  echo "Hyprland autostart has no duplicate Steam launch."
fi

[[ -f "$HOME/.config/autostart/steam.desktop" ]] ||
  echo "Note: enable Steam > Settings > Interface > Run Steam when my computer starts."
