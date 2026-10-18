#!/usr/bin/env bash
# PS5 Steam Big Picture helper at the pinned STEAM_HELPER_REF: install|check|dry-run.
# The helper is cloned from STEAM_HELPER_REPOSITORY into a cache when no local
# checkout exists, and the pinned commit (not the checkout's HEAD) is installed.
set -uo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f "$config_file" ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../../config/machine.example.env
source "$config_file"

action=${1:-check}
cache_dir=${STEAM_HELPER_DIR:-$HOME/.local/state/omarchy-gaming-setup/src/ps5-steam-big-picture}
monitor="$HOME/.local/bin/ps5-steam-big-picture-monitor"
service=ps5-steam-big-picture.service
staging=

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR Steam helper: %s\n' "$*" >&2; exit 1; }

# A checkout that already has the pinned commit: the cache, or a checkout next
# to this repository on the development machine. Never clones or fetches.
local_checkout() {
  local candidate
  for candidate in "$cache_dir" "$(CDPATH= cd -- "$repo_dir/.." && pwd)/ps5-steam-big-picture"; do
    git -C "$candidate" cat-file -e "${STEAM_HELPER_REF}^{commit}" 2>/dev/null && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

# Like local_checkout, but clones or fetches into the cache when needed.
helper_checkout() {
  local_checkout && return 0
  if [[ ! -d $cache_dir/.git ]]; then
    mkdir -p -- "$(dirname -- "$cache_dir")" || return 1
    git clone --quiet "$STEAM_HELPER_REPOSITORY" "$cache_dir" >&2 || return 1
  fi
  git -C "$cache_dir" fetch --quiet origin >&2 || return 1
  git -C "$cache_dir" cat-file -e "${STEAM_HELPER_REF}^{commit}" 2>/dev/null || return 1
  printf '%s\n' "$cache_dir"
}

dry_run() {
  say "Steam helper: $STEAM_HELPER_REPOSITORY at ${STEAM_HELPER_REF:0:7} (cache: $cache_dir)"
  say "Install and enable: $monitor, $service"
}

check() {
  local failures=0 checkout
  ok() { printf 'OK   Steam helper: %s\n' "$*"; }
  fail() { printf 'WARN Steam helper: %s\n' "$*"; failures=$((failures + 1)); }

  [[ -x $monitor ]] && ok "monitor installed ($monitor)" || fail "monitor missing: $monitor"
  checkout=$(local_checkout)
  if [[ -n $checkout && -x $monitor ]]; then
    git -C "$checkout" show "$STEAM_HELPER_REF:ps5-steam-big-picture-monitor" | cmp -s - "$monitor" \
      && ok "monitor matches pinned ${STEAM_HELPER_REF:0:7}" || fail "monitor differs from pinned ${STEAM_HELPER_REF:0:7}"
  fi
  systemctl --user is-enabled --quiet "$service" && ok "$service is enabled" || fail "$service is not enabled"
  systemctl --user is-active --quiet "$service" && ok "$service is active" || fail "$service is not active"
  return "$failures"
}

install_component() {
  local checkout
  command -v git >/dev/null 2>&1 || die "git is required"
  checkout=$(helper_checkout) || die "cannot get commit $STEAM_HELPER_REF from $STEAM_HELPER_REPOSITORY"
  staging=$(mktemp -d) || die "cannot create a staging directory"
  trap '[[ -z $staging ]] || rm -rf -- "$staging"' EXIT
  git -C "$checkout" archive "$STEAM_HELPER_REF" | tar -x -C "$staging" || die "cannot extract $STEAM_HELPER_REF"
  say "Installing the Steam Big Picture helper ${STEAM_HELPER_REF:0:7} from $checkout"
  "$staging/install.sh" || die "helper install.sh failed"
}

case $action in
  install) install_component ;;
  check) check ;;
  dry-run) dry_run ;;
  *) die "unknown action '$action' (install|check|dry-run)" ;;
esac
