#!/usr/bin/env bash
# Non-mutating PCSX2 checks. Pass --diagnose to also print the wrapper's
# controller diagnostics.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
wrapper="$HOME/.local/bin/omarchy-pcsx2"
ini="$HOME/.config/PCSX2/inis/PCSX2.ini"
failures=0
ok() { printf 'OK   PCSX2: %s\n' "$*"; }
fail() { printf 'WARN PCSX2: %s\n' "$*"; failures=$((failures + 1)); }

[[ -x $wrapper ]] && cmp -s "$component_dir/pcsx2-launch" "$wrapper" \
  && ok "wrapper installed ($wrapper)" || fail "wrapper missing or outdated: $wrapper"
appimage=$(find "$HOME/Applications" -maxdepth 1 -type f -iname 'pcsx2*.AppImage' -perm -u+x -print -quit 2>/dev/null)
[[ -n ${PCSX2_APPIMAGE:-$appimage} ]] && ok "AppImage found (${PCSX2_APPIMAGE:-$appimage})" \
  || fail "no executable pcsx2*.AppImage in $HOME/Applications"
[[ -f $ini ]] && ok "settings exist ($ini)" || fail "no $ini; run PCSX2 once, then rerun setup"
pacman -Q steam-devices >/dev/null 2>&1 && ok "steam-devices is installed" || fail "steam-devices is not installed"

[[ ${1:-} != --diagnose || ! -x $wrapper ]] || "$wrapper" --omarchy-diagnose
exit "$failures"
