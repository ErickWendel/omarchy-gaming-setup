#!/usr/bin/env bash
set -euo pipefail

wrapper="$HOME/.local/bin/omarchy-pcsx2"
[[ -x $wrapper ]] || { echo "FAIL PCSX2 wrapper missing: $wrapper"; exit 1; }
[[ -x "$HOME/Applications/pcsx2-Qt.AppImage" ]] || {
  echo "FAIL PCSX2 AppImage missing or not executable"; exit 1;
}
pacman -Q steam-devices >/dev/null 2>&1 || { echo "FAIL steam-devices is not installed"; exit 1; }
"$wrapper" --omarchy-diagnose

