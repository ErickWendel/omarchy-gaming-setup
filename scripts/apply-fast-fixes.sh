#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
projects_dir=$(CDPATH= cd -- "$repo_dir/.." && pwd)
delta_repo="$projects_dir/delta-cw360lcd-linux-driver"
steam_repo="$projects_dir/ps5-steam-big-picture"

[[ -x "$delta_repo/scripts/install-user-service.sh" ]] || {
  echo "Missing Delta migration helper: $delta_repo/scripts/install-user-service.sh" >&2
  exit 2
}
[[ -x "$steam_repo/install.sh" ]] || {
  echo "Missing Steam helper installer: $steam_repo/install.sh" >&2
  exit 2
}

echo "[1/4] Configuring OpenRGB startup"
"$repo_dir/setup.sh"

echo "[2/4] Migrating PCSX2 Steam shortcuts"
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

echo "[3/4] Migrating Delta Center to its hidden user service"
"$delta_repo/scripts/install-user-service.sh"

echo "[4/4] Updating the Steam Big Picture monitor service"
"$steam_repo/install.sh"

cat <<'EOF'

Fast fixes are installed. Do not close the GitHub issues yet.
Run the user-verification checklist in TESTING.md and report each result.
EOF

