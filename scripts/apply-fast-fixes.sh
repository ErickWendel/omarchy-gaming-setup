#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
projects_dir=$(CDPATH= cd -- "$repo_dir/.." && pwd)
delta_repo="$projects_dir/delta-cw360lcd-linux-driver"
steam_repo="$projects_dir/ps5-steam-big-picture"
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=config/machine.example.env
source "$config_file"

[[ -x "$delta_repo/scripts/install-user-service.sh" ]] || {
  echo "Missing Delta migration helper: $delta_repo/scripts/install-user-service.sh" >&2
  exit 2
}
[[ -d "$steam_repo/.git" ]] || {
  echo "Missing Steam helper checkout: $steam_repo" >&2
  exit 2
}
git -C "$steam_repo" cat-file -e "${STEAM_HELPER_REF}^{commit}" 2>/dev/null || {
  echo "Steam helper commit $STEAM_HELPER_REF is not in $steam_repo; run git fetch there." >&2
  exit 2
}

# Install the pinned commit, not whatever the helper checkout has locally.
steam_helper_dir=$(mktemp -d)
trap 'rm -rf "$steam_helper_dir"' EXIT
git -C "$steam_repo" archive "$STEAM_HELPER_REF" | tar -x -C "$steam_helper_dir"

echo "[1/5] Configuring OpenRGB startup"
"$repo_dir/setup.sh"

echo "[2/5] Migrating PCSX2 Steam shortcuts"
if pgrep -x steam >/dev/null 2>&1; then
  echo "Asking Steam to exit before editing its configuration"
  steam -shutdown
  for _ in {1..20}; do
    pgrep -x steam >/dev/null 2>&1 || break
    sleep 1
  done
  pgrep -x steam >/dev/null 2>&1 && {
    echo "Steam did not exit; close it manually and rerun this script." >&2
    exit 2
  }
fi
"$repo_dir/components/pcsx2/install.sh"

echo "[3/5] Migrating Delta Center to its hidden user service"
"$delta_repo/scripts/install-user-service.sh"

echo "[4/5] Removing the duplicate Steam autostart"
"$repo_dir/components/steam/install.sh"

echo "[5/5] Updating the Steam Big Picture monitor service (${STEAM_HELPER_REF:0:7})"
"$steam_helper_dir/install.sh"

cat <<'EOF'

Fast fixes are installed. Do not close the GitHub issues yet.
Run the user-verification checklist in TESTING.md and report each result.
EOF

