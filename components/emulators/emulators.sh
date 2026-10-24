#!/usr/bin/env bash
# Emulator application-menu entries and Steam shortcuts.
#
#   emulators.sh install|check|dry-run         menu entries
#   emulators.sh steam install|check|dry-run   non-Steam shortcuts (install needs Steam closed)
#
# Writes only below ~/.local/share/applications and the Steam user's
# shortcuts.vdf; never writes to GExtended.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$component_dir/../.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../../config/machine.example.env
source "$config_file"

script=emulators.py
extra=(--expected-mount "$GEXTENDED_MOUNT")
if [[ ${1:-} == steam ]]; then
  script=steam_shortcuts.py
  extra=(${STEAM_USER_ID:+--steam-user "$STEAM_USER_ID"})
  shift
fi
action=${1:-check}
case $action in
  install|check|dry-run) ;;
  *) printf 'ERROR emulators: unknown action %s ([steam] install|check|dry-run)\n' "$action" >&2; exit 2 ;;
esac
exec python3 -I "$component_dir/$script" "$action" --uuid "$GEXTENDED_UUID" "${extra[@]}"
