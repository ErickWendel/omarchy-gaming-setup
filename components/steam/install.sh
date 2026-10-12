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

# Match Proton games' saved resolution to the current monitor (ultrawide or
# 4K TV) before each launch; a mismatched exclusive-fullscreen mode makes
# Proton cover the game with an empty black window.
component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
wrapper="$HOME/.local/bin/omarchy-match-resolution"
install -Dm755 "$component_dir/match-resolution" "$wrapper"

mapfile -t localconfigs < <(find "${STEAM_ROOT:-$HOME/.local/share/Steam}/userdata" \
  -mindepth 3 -maxdepth 3 -path '*/config/localconfig.vdf' -type f -print 2>/dev/null)
if ((${#localconfigs[@]} != 1)); then
  echo "Expected one Steam user localconfig.vdf, found ${#localconfigs[@]}; set launch options manually:" >&2
  echo "  $wrapper %command%" >&2
elif pgrep -x steam >/dev/null 2>&1; then
  echo "Steam is running; exit it and rerun this script to set launch options."
else
  python "$component_dir/configure_launch_options.py" \
    --localconfig "${localconfigs[0]}" --wrapper "$wrapper"
fi
