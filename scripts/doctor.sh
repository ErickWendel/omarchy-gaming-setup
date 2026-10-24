#!/usr/bin/env bash
# Non-mutating report for every component. Exits with the number of failed
# components (0 when everything passes).
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../config/machine.example.env
set -a; source "$config_file"; set +a

failed=()
ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }

# Run a component check; its own lines explain each failed invariant.
component() {
  local name=$1; shift
  printf '\n== %s\n' "$name"
  if "$@"; then ok "$name checks passed"; else warn "$name needs attention"; failed+=("$name"); fi
}

hyprland_check() {
  local status=0 hypr="$HOME/.config/hypr" wrapper="$HOME/.local/bin/omarchy-match-resolution"
  if cmp -s "$repo_dir/components/hypr/gaming.lua" "$hypr/gaming.lua" &&
     grep -Fxq 'require("hypr.gaming")' "$hypr/hyprland.lua" 2>/dev/null; then
    ok "Hyprland: game window rules installed"
  else
    warn "Hyprland: game window rules missing or outdated: $hypr/gaming.lua"; status=1
  fi
  if [[ -x $wrapper ]] && cmp -s "$repo_dir/components/steam/match-resolution" "$wrapper"; then
    ok "Steam: resolution wrapper installed ($wrapper)"
  else
    warn "Steam: resolution wrapper missing or outdated: $wrapper"; status=1
  fi
  if [[ -f $HOME/.config/autostart/steam.desktop ]]; then
    ok "Steam: starts at login"
  else
    warn "Steam: enable Settings > Interface > Run Steam when my computer starts"; status=1
  fi
  return "$status"
}

storage_check() {
  local record target options
  record=$(findmnt -rn -o TARGET,UUID,OPTIONS 2>/dev/null | awk -v uuid="$GEXTENDED_UUID" '$2 == uuid { print; exit }')
  read -r target _ options <<<"$record"
  if [[ -z $target ]]; then
    warn "GExtended ($GEXTENDED_UUID) is not mounted; open it in the file manager or plug the disk in"
    return 1
  fi
  ok "GExtended is mounted at $target"
  [[ ,$options, == *,rw,* ]] && ok "GExtended is read-write" || { warn "GExtended is read-only ($options); repair manually"; return 1; }
  [[ $target == "$GEXTENDED_MOUNT" ]] || { warn "GExtended expected at $GEXTENDED_MOUNT"; return 1; }
}

desktop_entries_check() {
  local entry invalid=0
  command -v desktop-file-validate >/dev/null 2>&1 || { warn "desktop-file-validate is missing"; return 1; }
  while IFS= read -r -d '' entry; do
    desktop-file-validate "$entry" >/dev/null 2>&1 || { warn "invalid desktop entry: $entry"; invalid=$((invalid + 1)); }
  done < <(find "$HOME/.local/share/applications" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
  ((invalid == 0)) && ok "user desktop entries validate"
  ((invalid == 0))
}

printf 'Configuration: %s\n' "$config_file"
command -v omarchy >/dev/null 2>&1 && ok "Omarchy command is available" || { warn "Omarchy command is missing"; failed+=(Omarchy); }

component Packages "$repo_dir/scripts/packages.sh" check
component OpenRGB "$repo_dir/scripts/openrgb.sh" check
component Delta "$repo_dir/scripts/delta.sh" check
component "G29 wheel" "$repo_dir/components/g29/g29.sh" check
component "G923 wheel" "$repo_dir/components/g923/g923.sh" check
component Handbrake "$repo_dir/components/handbrake/handbrake.sh" check
component "Hyprland and Steam" hyprland_check
component "Emulator menu entries" "$repo_dir/components/emulators/emulators.sh" check
component "Steam helper" "$repo_dir/components/steam/helper.sh" check
component PCSX2 "$repo_dir/components/pcsx2/check.sh"
component "Assetto Corsa" "$repo_dir/components/assetto-corsa/assetto-corsa.sh" check
component "NFS Underground 2" "$repo_dir/components/nfsu2/nfsu2.sh" check
component "PCSX2 with DLSS 5" "$repo_dir/components/pcsx2-dlss5/pcsx2-dlss5.sh" check
component Storage storage_check
component "Desktop entries" desktop_entries_check

printf '\n'
if ((${#failed[@]})); then
  printf 'Components that need attention: %s\n' "$(printf '%s, ' "${failed[@]}" | sed 's/, $//')"
  exit "${#failed[@]}"
fi
echo "All components passed."
