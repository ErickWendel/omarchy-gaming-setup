#!/usr/bin/env bash
# Forza Horizon 5 rev lights on the G923: install|check|dry-run|uninstall.
# install edits Steam's config, so it needs Steam closed. The in-game Data Out
# setting lives in FH5's profile save and is set by hand (see README.md).
# check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
appid=1551360
steam_root=${FH5_STEAM_ROOT:-$HOME/.local/share/Steam}
bin_dir=${FH5_BIN_DIR:-$HOME/.local/bin}
wrapper_src="$component_dir/forza-rev-lights"
wrapper_dst="$bin_dir/omarchy-forza-rev-lights"
backup_root=${FH5_BACKUP_DIR:-$HOME/.local/state/omarchy-gaming-setup/backups}
steam_process=${FH5_STEAM_PROCESS:-steam}

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN forza-horizon-5: %s\n' "$*" >&2; }
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }
steam_running() { pgrep -x "$steam_process" >/dev/null 2>&1; }
localconfigs() {
  find "$steam_root/userdata" -mindepth 3 -maxdepth 3 -path "*/userdata/${STEAM_USER_ID:-*}/config/localconfig.vdf" -type f 2>/dev/null
}
# Edits FH5's launch options; $1 is empty to add the wrapper or --remove.
configure_steam() {
  if steam_running; then
    warn "Steam is running; exit Steam and rerun to change the launch options"
    return 1
  fi
  local configs
  mapfile -t configs < <(localconfigs)
  ((${#configs[@]} == 1)) || { warn "expected one Steam localconfig.vdf, found ${#configs[@]} (set STEAM_USER_ID)"; return 1; }
  python3 -I "$component_dir/configure_steam.py" --localconfig "${configs[0]}" --appid "$appid" \
    --wrapper "$wrapper_dst" --backup-dir "$backup_root" ${1:+"$1"}
}

dry_run() {
  say "Install rev-light wrapper: $wrapper_dst"
  say "Steam launch options (Steam closed): put $wrapper_dst right before %command%"
  say "In game, by hand: Settings > HUD and Gameplay > Data Out On, 127.0.0.1, port 5300"
}

install_component() {
  local failed=0
  command -v logi-tf-sim >/dev/null 2>&1 || warn "logi-tf-sim is missing; run scripts/packages.sh install (logi-wheel)"
  if same "$wrapper_src" "$wrapper_dst" || install -Dm755 "$wrapper_src" "$wrapper_dst"; then
    say "Rev-light wrapper installed: $wrapper_dst"
  else
    failed=1
  fi
  configure_steam || failed=1
  say "Set Data Out in game if it is not on yet: Settings > HUD and Gameplay, 127.0.0.1, port 5300"
  return "$failed"
}

uninstall_component() {
  local status=0
  configure_steam --remove || status=1
  rm -f -- "$wrapper_dst"
  say "Removed $wrapper_dst"
  return "$status"
}

check_component() {
  local failures=0 configs
  ok() { printf 'OK   forza-horizon-5: %s\n' "$*"; }
  fail() { printf 'FAIL forza-horizon-5: %s\n' "$*"; failures=$((failures + 1)); }

  same "$wrapper_src" "$wrapper_dst" && ok "rev-light wrapper installed" || fail "wrapper missing or outdated: $wrapper_dst"
  command -v logi-tf-sim >/dev/null 2>&1 && ok "logi-tf-sim installed" || fail "logi-tf-sim missing (package logi-wheel)"
  mapfile -t configs < <(localconfigs)
  if ((${#configs[@]} == 1)) && grep -Fq "$wrapper_dst %command%" "${configs[0]}"; then
    ok "Steam launch options use the wrapper"
  else
    fail "Steam launch options do not use $wrapper_dst (exit Steam and rerun install)"
  fi
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) printf 'ERROR forza-horizon-5: unknown action %s (install|check|dry-run|uninstall)\n' "$action" >&2; exit 2 ;;
esac
