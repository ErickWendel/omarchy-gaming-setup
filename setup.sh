#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=config/machine.example.env
source "$config_file"

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
      sed -n '2,24p' "$0"
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

case "$mode" in
  check)
    exec "$repo_dir/scripts/doctor.sh"
    ;;
  dry-run)
    echo "Configuration: $config_file"
    echo "GExtended: UUID=$GEXTENDED_UUID expected_mount=$GEXTENDED_MOUNT"
    echo "OpenRGB profile: $OPENRGB_PROFILE"
    [[ -z "$delta_archive" ]] || echo "Delta archive: $delta_archive"
    echo "Planned modules: storage guard, OpenRGB, Delta, Steam, emulator entries, PCSX2, G29 wheel, handbrake"
    "$repo_dir/scripts/openrgb.sh" dry-run
    "$repo_dir/scripts/delta.sh" dry-run ${delta_archive:+--archive "$delta_archive"}
    "$repo_dir/components/g29/g29.sh" dry-run
    "$repo_dir/components/handbrake/handbrake.sh" dry-run
    ;;
  install)
    # Components are independent: one failure must not block the others.
    failed=()
    "$repo_dir/scripts/openrgb.sh" install || failed+=(OpenRGB)
    "$repo_dir/scripts/delta.sh" install ${delta_archive:+--archive "$delta_archive"} || failed+=(Delta)
    "$repo_dir/components/g29/g29.sh" install || failed+=(G29)
    "$repo_dir/components/handbrake/handbrake.sh" install || failed+=(handbrake)
    echo "Remaining installation modules are still tracked in GitHub issues."
    if ((${#failed[@]})); then
      echo "Components that need attention: ${failed[*]}" >&2
      exit 1
    fi
    ;;
esac
