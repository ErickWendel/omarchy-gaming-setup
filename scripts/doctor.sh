#!/usr/bin/env bash
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../config/machine.example.env
source "$config_file"

failures=0
ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; failures=$((failures + 1)); }

if command -v omarchy >/dev/null 2>&1; then ok "Omarchy command is available"; else warn "Omarchy command is missing"; fi
if "$repo_dir/scripts/openrgb.sh" check; then
  ok "OpenRGB component checks passed"
else
  warn "OpenRGB component needs attention"
fi

if "$repo_dir/components/g29/g29.sh" check; then
  ok "G29 wheel component checks passed"
else
  warn "G29 wheel component needs attention"
fi
if "$repo_dir/components/handbrake/handbrake.sh" check; then
  ok "Handbrake component checks passed"
else
  warn "Handbrake component needs attention"
fi

mount_record=$(findmnt -rn -o TARGET,UUID,OPTIONS 2>/dev/null | awk -v uuid="$GEXTENDED_UUID" '$2 == uuid { print; exit }')
mount_target=$(awk '{ print $1 }' <<<"$mount_record")
mount_options=$(awk '{ print $3 }' <<<"$mount_record")
if [[ -z "$mount_target" ]]; then
  warn "GExtended ($GEXTENDED_UUID) is not mounted"
else
  ok "GExtended is mounted at $mount_target"
  if [[ ",$mount_options," == *,rw,* ]]; then ok "GExtended is read-write"; else warn "GExtended is read-only ($mount_options)"; fi
  [[ "$mount_target" == "$GEXTENDED_MOUNT" ]] || warn "Expected mount path is $GEXTENDED_MOUNT"
fi

if "$repo_dir/scripts/delta.sh" check; then
  ok "Delta component checks passed"
else
  warn "Delta component needs attention"
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
  invalid=0
  while IFS= read -r -d '' entry; do
    desktop-file-validate "$entry" >/dev/null 2>&1 || invalid=$((invalid + 1))
  done < <(find "$HOME/.local/share/applications" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
  if ((invalid == 0)); then ok "User desktop entries validate"; else warn "$invalid user desktop entries are invalid"; fi
fi

exit "$failures"
