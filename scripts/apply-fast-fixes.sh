#!/usr/bin/env bash
# Kept for older notes: setup.sh now installs every module, including the
# PCSX2, Steam, Hyprland and Steam helper fixes this script used to apply.
exec "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/setup.sh" "$@"
