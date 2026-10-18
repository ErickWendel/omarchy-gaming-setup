#!/usr/bin/env bash
# System packages the components need: install|check|dry-run.
# install uses sudo (through omarchy-pkg-add when available) and only adds
# missing packages; check and dry-run change nothing.
set -uo pipefail

action=${1:-check}

# Official repositories (Steam needs multilib, which Omarchy enables).
packages=(
  git python python-vdf python-evdev unzip desktop-file-utils # setup helpers
  openrgb                                                     # OpenRGB
  steam steam-devices                                         # Steam, PCSX2 controller access
  protontricks                                                # Assetto Corsa prefix
)
# AUR, optional: the G29 also works with the in-kernel hid-logitech driver.
aur_packages=(new-lg4ff-dkms-git)

say() { printf '%s\n' "$*"; }
missing() { local pkg; for pkg in "$@"; do pacman -Q "$pkg" >/dev/null 2>&1 || printf '%s\n' "$pkg"; done; }

dry_run() {
  say "Install missing packages (sudo): ${packages[*]}"
  say "Install missing optional AUR packages: ${aur_packages[*]}"
}

check() {
  local failures=0 pkg
  for pkg in "${packages[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then printf 'OK   packages: %s\n' "$pkg"
    else printf 'WARN packages: %s is not installed\n' "$pkg"; failures=$((failures + 1)); fi
  done
  for pkg in "${aur_packages[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 && printf 'OK   packages: %s\n' "$pkg" \
      || printf 'INFO packages: optional %s is not installed\n' "$pkg"
  done
  return "$failures"
}

install_component() {
  local needed
  mapfile -t needed < <(missing "${packages[@]}")
  if ((${#needed[@]})); then
    say "Installing packages: ${needed[*]}"
    if command -v omarchy-pkg-add >/dev/null 2>&1; then
      omarchy-pkg-add "${needed[@]}" || { say "ERROR packages: installation failed" >&2; return 1; }
    else
      sudo pacman -S --needed --noconfirm "${needed[@]}" || { say "ERROR packages: installation failed" >&2; return 1; }
    fi
  else
    say "Required packages are installed"
  fi

  mapfile -t needed < <(missing "${aur_packages[@]}")
  ((${#needed[@]})) || return 0
  if command -v omarchy-pkg-aur-add >/dev/null 2>&1 && omarchy-pkg-aur-add "${needed[@]}"; then
    say "Installed optional AUR packages: ${needed[*]}"
  else
    say "WARN packages: optional ${needed[*]} not installed; continuing with the in-kernel driver"
  fi
}

case $action in
  install) install_component ;;
  check) check ;;
  dry-run) dry_run ;;
  *) say "ERROR packages: unknown action '$action' (install|check|dry-run)" >&2; exit 2 ;;
esac
