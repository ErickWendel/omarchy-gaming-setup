#!/usr/bin/env bash
# Restore the Omarchy gaming setup. Safe to rerun: every module only changes
# what differs from the versioned state, and backs up user files it replaces.
#
# Usage: ./setup.sh [--check | --dry-run] [--delta-archive PATH]
#
#   (no option)          install every module, then print a summary
#   --check              non-mutating doctor report; exits nonzero on failures
#   --dry-run            describe what install would change
#   --delta-archive PATH install the private Delta Center runtime from PATH
#
# Install asks for sudo (packages, udev rules, the handbrake service and boot
# entry) and exits Steam before it edits Steam's configuration. A missing
# private file or device only fails its own module; rerun after fixing it.
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# Export the settings so every module sees local overrides.
# shellcheck source=config/machine.example.env
set -a; source "$config_file"; set +a

mode=install
delta_archive=
while (($#)); do
  case "$1" in
    --check) mode=check ;;
    --dry-run) mode=dry-run ;;
    --delta-archive)
      shift
      (($#)) || { echo "--delta-archive requires a path" >&2; exit 2; }
      delta_archive=$1
      ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ -n "$delta_archive" && ! -f "$delta_archive" ]]; then
  echo "Delta archive not found: $delta_archive" >&2
  exit 2
fi

component() { printf '\n==> %s\n' "$*"; }

# Steam rewrites its configuration on exit, so edits are only safe while it
# is closed.
stop_steam() {
  pgrep -x steam >/dev/null 2>&1 || return 0
  echo "Asking Steam to exit before editing its configuration"
  steam -shutdown >/dev/null 2>&1 || true
  for _ in {1..30}; do
    pgrep -x steam >/dev/null 2>&1 || return 0
    sleep 1
  done
  echo "Steam did not exit; close it and rerun ./setup.sh" >&2
  return 1
}

case "$mode" in
  check)
    exec "$repo_dir/scripts/doctor.sh"
    ;;
  dry-run)
    echo "Configuration: $config_file"
    echo "GExtended: UUID=$GEXTENDED_UUID expected_mount=$GEXTENDED_MOUNT (checked only; repair in place with scripts/storage.sh fsck)"
    component Packages; "$repo_dir/scripts/packages.sh" dry-run
    component OpenRGB; "$repo_dir/scripts/openrgb.sh" dry-run
    component Delta; "$repo_dir/scripts/delta.sh" dry-run ${delta_archive:+--archive "$delta_archive"}
    component "G29 wheel"; "$repo_dir/components/g29/g29.sh" dry-run
    component "G923 wheel"; "$repo_dir/components/g923/g923.sh" dry-run
    component Handbrake; "$repo_dir/components/handbrake/handbrake.sh" dry-run
    component "Emulator menu entries"; "$repo_dir/components/emulators/emulators.sh" dry-run
    component "Hyprland game rules"
    echo "Install ~/.config/hypr/gaming.lua and require it from hyprland.lua"
    echo "Remove a duplicate Steam launch from ~/.config/hypr/autostart.lua"
    component "Steam (exits Steam first)"
    echo "Install ~/.local/bin/omarchy-match-resolution and add it to managed games' launch options"
    echo "Install ~/.local/bin/omarchy-pcsx2, apply PCSX2.ini settings, point PCSX2 shortcuts at it"
    component "Assetto Corsa"; "$repo_dir/components/assetto-corsa/assetto-corsa.sh" dry-run
    component "NFS Underground 2"; "$repo_dir/components/nfsu2/nfsu2.sh" dry-run
    component "NFS Most Wanted"; "$repo_dir/components/nfsmw/nfsmw.sh" dry-run
    component "PCSX2 with DLSS 5"; "$repo_dir/components/pcsx2-dlss5/pcsx2-dlss5.sh" dry-run
    component "Steam helper"; "$repo_dir/components/steam/helper.sh" dry-run
    ;;
  install)
    # Modules are independent: one failure must not block the others.
    failed=()
    run() {
      local name=$1; shift
      component "$name"
      "$@" || failed+=("$name")
    }
    run Packages "$repo_dir/scripts/packages.sh" install
    run OpenRGB "$repo_dir/scripts/openrgb.sh" install
    run Delta "$repo_dir/scripts/delta.sh" install ${delta_archive:+--archive "$delta_archive"}
    run "G29 wheel" "$repo_dir/components/g29/g29.sh" install
    run "G923 wheel" "$repo_dir/components/g923/g923.sh" install
    run Handbrake "$repo_dir/components/handbrake/handbrake.sh" install
    run "Hyprland game rules" "$repo_dir/components/hypr/install.sh"
    run "Emulator menu entries" "$repo_dir/components/emulators/emulators.sh" install
    if component "Stopping Steam" && stop_steam; then
      run Steam "$repo_dir/components/steam/install.sh"
      run PCSX2 "$repo_dir/components/pcsx2/install.sh"
      run "Assetto Corsa" "$repo_dir/components/assetto-corsa/assetto-corsa.sh" install
      run "NFS Most Wanted" "$repo_dir/components/nfsmw/nfsmw.sh" install
    else
      failed+=(Steam PCSX2 "Assetto Corsa" "NFS Most Wanted")
    fi
    run "NFS Underground 2" "$repo_dir/components/nfsu2/nfsu2.sh" install
    run "PCSX2 with DLSS 5" "$repo_dir/components/pcsx2-dlss5/pcsx2-dlss5.sh" install
    run "Steam helper" "$repo_dir/components/steam/helper.sh" install

    echo
    if ((${#failed[@]})); then
      printf 'Modules that need attention: %s\n' "$(printf '%s, ' "${failed[@]}" | sed 's/, $//')" >&2
      echo "Fix the reported prerequisite and rerun ./setup.sh; modules already in place make no changes." >&2
      exit 1
    fi
    echo "Setup finished. Reboot (kernel option and login services), then run ./setup.sh --check."
    ;;
esac
