#!/usr/bin/env bash
# Emulator application-menu entries: install|check|dry-run.
# Writes only below ~/.local/share/applications; never writes to GExtended.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$component_dir/../.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../../config/machine.example.env
source "$config_file"

action=${1:-check}
case $action in
  install|check|dry-run) ;;
  *) printf 'ERROR emulators: unknown action %s (install|check|dry-run)\n' "$action" >&2; exit 2 ;;
esac
exec python3 -I "$component_dir/emulators.py" "$action" \
  --uuid "$GEXTENDED_UUID" --expected-mount "$GEXTENDED_MOUNT"
