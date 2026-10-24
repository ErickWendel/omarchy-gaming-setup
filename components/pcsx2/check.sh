#!/usr/bin/env bash
# Non-mutating PCSX2 checks. Pass --diagnose to also print the wrapper's
# controller diagnostics.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
wrapper="$HOME/.local/bin/omarchy-pcsx2"
ini="$HOME/.config/PCSX2/inis/PCSX2.ini"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
failures=0
ok() { printf 'OK   PCSX2: %s\n' "$*"; }
note() { printf 'NOTE PCSX2: %s\n' "$*"; }
fail() { printf 'WARN PCSX2: %s\n' "$*"; failures=$((failures + 1)); }

[[ -x $wrapper ]] && cmp -s "$component_dir/pcsx2-launch" "$wrapper" \
  && ok "wrapper installed ($wrapper)" || fail "wrapper missing or outdated: $wrapper"
appimage=$(find "$HOME/Applications" -maxdepth 1 -type f -iname 'pcsx2*.AppImage' -perm -u+x -print -quit 2>/dev/null)
[[ -n ${PCSX2_APPIMAGE:-$appimage} ]] && ok "AppImage found (${PCSX2_APPIMAGE:-$appimage})" \
  || fail "no executable pcsx2*.AppImage in $HOME/Applications"
[[ -f $ini ]] && ok "settings exist ($ini)" || fail "no $ini; run PCSX2 once, then rerun setup"

# udev rules: steam-devices grants the session user access to controllers.
if ! pacman -Q steam-devices >/dev/null 2>&1; then
  fail "steam-devices is not installed (udev rules for controllers); run ./setup.sh"
elif [[ ! -f /usr/lib/udev/rules.d/60-steam-input.rules ]]; then
  fail "steam-devices is installed but 60-steam-input.rules is missing; reinstall steam-devices"
else
  ok "steam-devices udev rules are installed"
fi

# Controllers and their device ACLs. A missing pad is hardware, not setup.
if [[ -x $wrapper ]]; then
  mapfile -t pads < <("$wrapper" --omarchy-diagnose 2>/dev/null | sed -n 's/^controller=//p' | grep -v '^none$')
  sony=0 others=()
  for pad in "${pads[@]}"; do
    # Some mice expose a joystick node too.
    shopt -s nocasematch
    [[ $pad =~ mouse|mx\ master|keyboard|touchpad ]] && { shopt -u nocasematch; continue; }
    shopt -u nocasematch
    if [[ $pad == *readable=no ]]; then
      fail "no read access to ${pad% readable=no}; log out and back in, or check the steam-devices rules"
    fi
    case $pad in
      *"[054c:"*) sony=$((sony + 1)) ;;
      *) others+=("${pad%% \[*}") ;;
    esac
  done
  if ((sony == 0)); then
    note "no Sony controller connected; connect the pads to test them"
  else
    ok "$sony Sony controller(s) connected and readable"
  fi
  # PCSX2 binds player 1 and its hotkeys to SDL-0, which a wheel or
  # handbrake can take before the pads.
  if ((sony > 0 && ${#others[@]} > 0)); then
    note "other joysticks connected (${others[*]}); they may take SDL-0 before the pads, so remap Pad1 in PCSX2 or unplug them"
  fi
fi

# Steam interception: every PCSX2 shortcut must have Steam Input disabled.
mapfile -t shortcuts_files < <(find "$steam_root/userdata" -mindepth 3 -maxdepth 3 \
  -path "*/userdata/${STEAM_USER_ID:-*}/config/shortcuts.vdf" -type f -print 2>/dev/null)
if ((${#shortcuts_files[@]} == 1)) && [[ -x $wrapper ]]; then
  config_dir=${shortcuts_files[0]%/shortcuts.vdf}
  while IFS= read -r line; do
    case $line in
      *" PCSX2 shortcuts start the wrapper"*) ok "$line" ;;
      *) fail "$line" ;;
    esac
  done < <(python "$component_dir/configure_steam_shortcuts.py" --check \
    --shortcuts "$config_dir/shortcuts.vdf" --localconfig "$config_dir/localconfig.vdf" \
    --wrapper "$wrapper" 2>&1)
else
  note "Steam shortcuts not checked (no single Steam user; set STEAM_USER_ID)"
fi

[[ ${1:-} != --diagnose || ! -x $wrapper ]] || "$wrapper" --omarchy-diagnose
exit "$failures"
