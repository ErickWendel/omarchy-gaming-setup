#!/usr/bin/env bash
# Steam-only guest account: install|check|dry-run|uninstall. Run as the owner
# of the Steam install; install and uninstall use sudo.
#
# The account (STEAM_GUEST_USER, default guest) has no sudo, no desktop and no
# SSH: every login runs Steam's gamepad UI in a locked-down Hyprland, and quitting Steam
# logs out. It runs the owner's Steam install as it is (login, settings,
# launch options, shortcuts, Protons), sees nothing else of the owner's home,
# and has its own copies of the Proton prefixes. check and dry-run change
# nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=${1:-check}
guest=${STEAM_GUEST_USER-guest}
group=steam-only
owner=${USER:?}
owner_home=${HOME:?}
library=${STEAM_LIBRARY:-/wdblack_4TB/SteamLibrary}
games=${GAMES_DIR:-/wdblack_4TB/Games}
output=${STEAM_SESSION_OUTPUT:-}
client_args=${STEAM_CLIENT_ARGS:-}
# 1: turn Omarchy's autologin off so the boot shows the user list.
login_at_boot=${STEAM_GUEST_LOGIN_AT_BOOT:-1}
helpers=${STEAM_SESSION_HELPERS-}
# The owner's helper services and Hyprland game rules the guest also gets.
# Units are copied with %h pointing at the owner's home; the view exposes
# the paths they run from (read-only).
guest_units=${STEAM_GUEST_USER_UNITS-fullscreen-restore.service ps5-steam-big-picture.service omarchy-f1-2020-rev-lights.service openrgb.service delta-center.service}
guest_hypr_rules=${STEAM_GUEST_HYPR_RULES-gaming assettocorsa}
ro_paths=${STEAM_SHARED_RO_PATHS-.local/bin .local/lib/omarchy-gaming-setup .local/opt/delta-center}
# Test hook: prefix for every system path written or read.
root=${STEAM_GUEST_ROOT:-}
sudo_cmd=${STEAM_GUEST_SUDO-sudo}

steam=$owner_home/.local/share/Steam
library_compat=$library/steamapps/compatdata
steam_compat=$steam/steamapps/compatdata
# Root-owned, mode 000 parents of the guest's compatdata copies, on the same
# filesystem as the originals so the first copy is a free reflink.
library_instances=$(dirname -- "$library")/.steam-guest-compatdata
home_instances=$(dirname -- "$owner_home")/.steam-guest-compatdata
guest_home=$(getent passwd "$guest" 2>/dev/null | cut -d: -f6)
guest_home=${guest_home:-/home/$guest}
lib_dir=$root/usr/local/lib/omarchy-gaming-setup
session_src=$component_dir/omarchy-steam-session
session_dst=$root/usr/local/bin/omarchy-steam-session
view_src=$component_dir/omarchy-steam-guest-view
view_dst=$lib_dir/omarchy-steam-guest-view
user_pam_base=$root/usr/lib/pam.d/systemd-user
user_pam_file=$root/etc/pam.d/systemd-user
guest_config=$root$guest_home/.config
# Omarchy's lock screen; a passwordless guest needs the same rule there.
lock_pam_file=$root/etc/pam.d/omarchy-lock-password
profile_src=$component_dir/profile.sh
profile_dst=$root/etc/profile.d/omarchy-steam-only.sh
config_dst=$root/etc/omarchy-steam-session.conf
namespace_dst=$root/etc/security/namespace.d/omarchy-steam-guest.conf
sshd_dst=$root/etc/ssh/sshd_config.d/30-omarchy-steam-only.conf
# Omarchy's login theme only logs in the last user; this copy can pick one.
theme_src=$component_dir/sddm-theme
theme_dst=$root/usr/share/sddm/themes/omarchy-gaming
theme_base=$root/usr/share/sddm/themes/omarchy
theme_conf_dst=$root/etc/sddm.conf.d/zz-omarchy-gaming-theme.conf
pam_file=$root/etc/pam.d/sddm
# pam_namespace unshares the session's mounts (and swaps the library's
# compatdata); the view hook then mounts the shared Steam inside it.
pam_namespace_line='session    optional    pam_namespace.so mount_private'
pam_exec_line="session    optional    pam_exec.so quiet ${view_dst#"$root"}"
# No password on the login screen for steam-only members; the account's own
# password stays locked, so TTY, su and SSH still refuse it.
pam_auth_line="auth       sufficient  pam_succeed_if.so user ingroup $group quiet"
# Superseded: the guest no longer keeps a Steam install of its own.
legacy_files=("$lib_dir/omarchy-steam-library" "$root/usr/local/bin/steamos-session-select"
  "$root/usr/local/share/wayland-sessions/omarchy-steam.desktop")
legacy_dirs=("$root/etc/omarchy-steam-guest")

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR steam-guest: %s\n' "$*" >&2; exit 1; }
same() { [[ -r $2 ]] && cmp -s "$1" "$2"; }
same_text() { [[ -r $2 ]] && [[ $(<"$2") == "$1" ]]; }

config_text() {
  printf '# Managed by omarchy-gaming-setup (components/steam-guest).\n'
  printf 'STEAM_LIBRARY=%q\nSTEAM_GAMES_DIR=%q\nSTEAM_SESSION_OUTPUT=%q\n' "$library" "$games" "$output"
  printf 'STEAM_SHARED_OWNER=%q\nSTEAM_SHARED_HOME=%q\n' "$owner" "$owner_home"
  printf 'STEAM_GUEST_HOME_INSTANCES=%q\n' "$home_instances"
  printf '# Extra flags for the guest'"'"'s Steam client.\nSTEAM_CLIENT_ARGS=%q\n' "$client_args"
  printf '# Started beside Steam for the session.\nSTEAM_SESSION_HELPERS=%q\n' "$helpers"
  printf '# Owner paths the guest sees read-only (helper services, launch wrappers).\nSTEAM_SHARED_RO_PATHS=%q\n' "$ro_paths"
}
# systemd's own stack plus the view, so apps and services the guest's user
# manager starts (Steam from autostart, helper services) see it too.
user_pam_text() {
  printf '# Managed by omarchy-gaming-setup (components/steam-guest): %s\n' "${user_pam_base#"$root"}"
  printf '# plus the shared Steam view for %s members. Regenerated by install.\n' "$group"
  cat -- "$user_pam_base"
  printf '%s\n%s\n' "$pam_namespace_line" "$pam_exec_line"
}
namespace_text() {
  printf '# Managed by omarchy-gaming-setup (components/steam-guest).\n'
  printf '# Give %s a private steamapps/compatdata: Wine refuses prefixes owned by\n' "$guest"
  printf '# another user, and the shared library'"'"'s prefixes belong to its owner.\n'
  printf '%s %s/ user ~%s\n' "$library_compat" "$library_instances" "$guest"
}
theme_conf_text() {
  printf '# Managed by omarchy-gaming-setup (components/steam-guest): Omarchy theme\n'
  printf '# with a user switcher. Sorted after 99-omarchy-login.conf to override it.\n'
  printf '[Theme]\nCurrent=omarchy-gaming\n'
  [[ $login_at_boot == 1 ]] || return 0
  printf '\n# Overrides autologin.conf so boot shows the user list (STEAM_GUEST_LOGIN_AT_BOOT=1).\n'
  printf '[Autologin]\nUser=\nSession=\n'
}
theme_current() {
  local file
  for file in "$theme_src"/*; do same "$file" "$theme_dst/${file##*/}" || return 1; done
  same_text "$(theme_conf_text)" "$theme_conf_dst"
}
# Our Main.qml and metadata; the images come from Omarchy's theme.
install_theme() {
  local file
  [[ -d $theme_base ]] || { say "No Omarchy SDDM theme at ${theme_base#"$root"}; pick $guest by name in your theme"; return 0; }
  for file in "$theme_src"/*; do install_file 644 "$file" "$theme_dst/${file##*/}"; done
  for file in "$theme_base"/*.png "$theme_base"/theme.conf; do
    [[ -e $file && ! -e $theme_dst/${file##*/} ]] || continue
    $sudo_cmd ln -s -- "${file#"$root"}" "$theme_dst/${file##*/}" || die "cannot link ${file##*/} into $theme_dst"
  done
  install_text 644 "$(theme_conf_text)" "$theme_conf_dst"
}
sshd_text() {
  printf '# Managed by omarchy-gaming-setup: Steam-only accounts get no shell.\n'
  printf 'DenyGroups %s\n' "$group"
}
user_groups() { id -nG "$guest" 2>/dev/null | tr ' ' '\n'; }
has_acl() { getfacl -pE -- "$1" 2>/dev/null | grep -Fxq "$2"; }
granted() { has_acl "$root$1" "default:user:$guest:rwx"; }

dry_run() {
  say "Create user $guest (no sudo) in group $group"
  say "Install the guest desktop session wrapper: ${session_dst#"$root"} (Omarchy desktop, Steam Big Picture at login)"
  say "Force $group members into it at every login: ${profile_dst#"$root"}"
  say "Share $steam with $guest: ${view_dst#"$root"} via pam_exec, $guest_home/.local/share/Steam symlink"
  say "Private Proton prefixes, first copied from $owner's: $library_instances/$guest, $home_instances/$guest"
  say "Block SSH for $group: ${sshd_dst#"$root"}"
  say "Login screen user switcher: ${theme_dst#"$root"} via ${theme_conf_dst#"$root"}"
  [[ $login_at_boot == 1 ]] && say "Turn off autologin so boot shows the user list (STEAM_GUEST_LOGIN_AT_BOOT=0 keeps it)"
  say "Grant $guest and $owner read/write ACLs on $steam, $library and $games (except compatdata)"
}

# Named-user ACLs for both accounts on every file and directory of a tree,
# inherited by new files. The owner's Proton prefixes stay theirs.
grant_tree() {
  local tree=$1 entries="u:$guest:rwX,u:$owner:rwX"
  [[ -d $root$tree ]] || return 0
  granted "$tree" && return 0
  say "Granting $guest access to $tree (this walks every file)"
  $sudo_cmd find "$root$tree" -path "$root$tree/steamapps/compatdata" -prune -o \( -type d -o -type f \) -print0 |
    $sudo_cmd xargs -0r setfacl -P -m "$entries" -- || die "setfacl failed on $tree"
  $sudo_cmd find "$root$tree" -path "$root$tree/steamapps/compatdata" -prune -o -type d -print0 |
    $sudo_cmd xargs -0r setfacl -P -d -m "$entries" -- || die "default setfacl failed on $tree"
}

# The guest's prefixes start as copies of the owner's, saves included. Only
# prefixes the guest does not have yet are copied.
seed_prefixes() { # source destination
  local source=$1 destination=$2 prefix name
  $sudo_cmd test -d "$root$destination/$guest" ||
    $sudo_cmd install -d -m 700 -o "$guest" -g "$guest" "$root$destination/$guest" || die "cannot create $destination/$guest"
  # pam_namespace requires the instance parent to be root's with mode 000.
  $sudo_cmd chown root:root "$root$destination" && $sudo_cmd chmod 000 "$root$destination" \
    || die "cannot lock down $destination"
  for prefix in "$root$source"/*/; do
    [[ -d $prefix ]] || continue
    name=$(basename -- "$prefix")
    $sudo_cmd test -e "$root$destination/$guest/$name" && continue
    $sudo_cmd cp -a --reflink=auto -- "${prefix%/}" "$root$destination/$guest/$name" &&
      $sudo_cmd chown -R "$guest:$guest" "$root$destination/$guest/$name" || die "cannot copy prefix $name"
    say "Copied Proton prefix $name for $guest"
  done
}

# Directories under the guest's home, owned by the guest.
guest_dirs() {
  local dir
  for dir in "$@"; do
    $sudo_cmd install -d -m 755 -o "$guest" -g "$guest" "$dir" || die "cannot create $dir"
  done
}
guest_text() { # text destination
  $sudo_cmd test -f "$2" && [[ $($sudo_cmd cat -- "$2") == "$1" ]] && return 0
  printf '%s\n' "$1" | $sudo_cmd install -m 644 -o "$guest" -g "$guest" /dev/stdin "$2" || die "cannot write $2"
  say "Installed ${2#"$root"}"
}
# The owner's game window rules, required from the guest's hyprland.lua.
install_guest_hypr() {
  local name source config=$guest_config/hypr/hyprland.lua
  $sudo_cmd test -f "$config" || { say "No ${config#"$root"} yet; game rules skipped (rerun after $guest's first login)"; return 0; }
  for name in $guest_hypr_rules; do
    source=$root$owner_home/.config/hypr/$name.lua
    [[ -r $source ]] || continue
    guest_text "$(<"$source")" "$guest_config/hypr/$name.lua"
    $sudo_cmd grep -Fxq "require(\"hypr.$name\")" "$config" && continue
    printf '\n-- Game window rules managed by omarchy-gaming-setup (steam-guest).\nrequire("hypr.%s")\n' "$name" |
      $sudo_cmd tee -a "$config" >/dev/null || die "cannot edit $config"
    say "Added require(\"hypr.$name\") to ${config#"$root"}"
  done
}
# The owner's helper services, enabled for the guest's user manager.
install_guest_units() {
  local unit source target dir=$guest_config/systemd/user
  guest_dirs "$guest_config" "$guest_config/systemd" "$dir"
  for unit in $guest_units; do
    source=$root$owner_home/.config/systemd/user/$unit
    [[ -r $source ]] || { say "No $unit for $owner; skipped"; continue; }
    guest_text "$(sed "s|%h|$owner_home|g" "$source")" "$dir/$unit"
    for target in $(sed -n 's/^WantedBy=//p' "$source"); do
      guest_dirs "$dir/$target.wants"
      $sudo_cmd ln -sfn -- "../$unit" "$dir/$target.wants/$unit" &&
        $sudo_cmd chown -h "$guest:$guest" "$dir/$target.wants/$unit" || die "cannot enable $unit for $guest"
    done
  done
}

install_file() { # mode source destination
  same "$2" "$3" && return 0
  $sudo_cmd install -Dm"$1" "$2" "$3" || die "cannot install $3"
  say "Installed ${3#"$root"}"
}
install_text() { # mode text destination
  same_text "$2" "$3" && return 0
  printf '%s\n' "$2" | $sudo_cmd install -Dm"$1" /dev/stdin "$3" || die "cannot install $3"
  say "Installed ${3#"$root"}"
}
# Before the first auth line, so it answers before the password prompt.
add_pam_auth_line() { # file
  local file=$1
  grep -Fxq "$pam_auth_line" "$file" && return 0
  grep -q '^auth[[:space:]]' "$file" || die "no auth lines in $file"
  $sudo_cmd sed -i "0,/^auth[[:space:]]/s//${pam_auth_line}\n&/" "$file" || die "cannot edit $file"
  say "Added to ${file#"$root"}: $pam_auth_line"
}
first_auth_is_ours() { [[ $(grep -m1 '^auth[[:space:]]' "$1" 2>/dev/null) == "$pam_auth_line" ]]; }
add_pam_line() {
  grep -Fxq "$1" "$pam_file" && return 0
  printf '%s\n' "$1" | $sudo_cmd tee -a "$pam_file" >/dev/null || die "cannot edit $pam_file"
  say "Added to ${pam_file#"$root"}: $1"
}

install_component() {
  ((EUID != 0)) || die "run as the owner of the Steam install, not root"
  command -v uwsm >/dev/null 2>&1 || die "uwsm (Omarchy's session manager) is required"
  command -v steam >/dev/null 2>&1 || die "steam is required"
  [[ -d $root$steam && ! -L $root$steam ]] || die "no Steam install at $steam"
  [[ -d $root$library/steamapps/common ]] || die "Steam library not found: $library"
  [[ -f $pam_file ]] || die "missing $pam_file (is SDDM the login manager?)"

  getent group "$group" >/dev/null || { $sudo_cmd groupadd --system "$group" || die "cannot create group $group"; }
  if ! getent passwd "$guest" >/dev/null; then
    $sudo_cmd useradd --create-home --shell /usr/bin/bash --groups "$group" --comment "Steam guest" "$guest" \
      || die "cannot create user $guest"
    say "Created user $guest"
  fi
  user_groups | grep -Fxq "$group" || { $sudo_cmd gpasswd -a "$guest" "$group" >/dev/null || die "cannot add $guest to $group"; }
  if user_groups | grep -Fxq wheel; then
    $sudo_cmd gpasswd -d "$guest" wheel >/dev/null || die "cannot remove $guest from wheel"
    say "Removed $guest from wheel (sudo)"
  fi

  install_file 755 "$session_src" "$session_dst"
  install_file 755 "$view_src" "$view_dst"
  install_file 644 "$profile_src" "$profile_dst"
  install_text 644 "$(config_text)" "$config_dst"
  install_text 644 "$(namespace_text)" "$namespace_dst"
  # Earlier versions: own Steam install, gamescope and kiosk Hyprland sessions.
  local legacy
  for legacy in "${legacy_files[@]}"; do [[ ! -e $legacy ]] || $sudo_cmd rm -f -- "$legacy"; done
  for legacy in "${legacy_dirs[@]}"; do [[ ! -d $legacy ]] || $sudo_cmd rm -r -- "$legacy"; done

  seed_prefixes "$library_compat" "$library_instances"
  seed_prefixes "$steam_compat" "$home_instances"

  # The guest's Steam is the owner's: ~/.local/share/Steam points at it.
  local link=$root$guest_home/.local/share/Steam
  if [[ $($sudo_cmd readlink -- "$link") != "$steam" ]]; then
    if $sudo_cmd test -e "$link" -a ! -L "$link"; then
      $sudo_cmd mv -- "$link" "$link.before-shared" || die "cannot move $link aside"
      say "Moved $guest's own Steam install to $link.before-shared"
    fi
    $sudo_cmd install -d -o "$guest" -g "$guest" "$root$guest_home/.local" "$root$guest_home/.local/share" &&
      $sudo_cmd ln -sfn -- "$steam" "$link" && $sudo_cmd chown -h "$guest:$guest" "$link" \
      || die "cannot link $link"
    say "Linked ${link#"$root"} -> $steam"
  fi

  add_pam_line "$pam_namespace_line"
  add_pam_line "$pam_exec_line"
  if [[ -r $user_pam_base ]]; then
    install_text 644 "$(user_pam_text)" "$user_pam_file"
  else
    say "No ${user_pam_base#"$root"}; apps the guest's user manager starts will not see the shared Steam"
  fi
  install_guest_units
  install_guest_hypr
  add_pam_auth_line "$pam_file"
  if [[ -f $lock_pam_file ]]; then
    add_pam_auth_line "$lock_pam_file"
  else
    say "No ${lock_pam_file#"$root"}; $guest may not be able to unlock an idle lock screen"
  fi
  $sudo_cmd passwd -l "$guest" >/dev/null || die "cannot lock $guest's password"
  install_theme

  if [[ -d $root/etc/ssh/sshd_config.d ]] && ! same_text "$(sshd_text)" "$sshd_dst"; then
    install_text 644 "$(sshd_text)" "$sshd_dst"
    if systemctl is-active --quiet sshd; then
      $sudo_cmd sshd -t || die "sshd rejected ${sshd_dst#"$root"}; remove it"
      $sudo_cmd systemctl reload sshd || die "cannot reload sshd"
    fi
  fi

  grant_tree "$library"
  grant_tree "$steam"
  grant_tree "$games"
  say "Log out, then pick $guest on the login screen and press Enter (no password)."
}

uninstall_component() {
  local tree pattern
  $sudo_cmd rm -f -- "$session_dst" "$view_dst" "$profile_dst" "$config_dst" "$namespace_dst" \
    "$sshd_dst" "$theme_conf_dst" "${legacy_files[@]}" || die "cannot remove installed files"
  for pattern in "${legacy_dirs[@]}"; do [[ ! -d $pattern ]] || $sudo_cmd rm -r -- "$pattern"; done
  if grep -Fxq "$pam_auth_line" "$lock_pam_file" 2>/dev/null; then
    $sudo_cmd sed -i "\\|^${pam_auth_line}\$|d" "$lock_pam_file" || die "cannot edit $lock_pam_file"
  fi
  [[ ! -d $theme_dst ]] || $sudo_cmd rm -r -- "$theme_dst" || die "cannot remove $theme_dst"
  # Ours only while it is the generated copy; otherwise just drop our lines.
  if [[ -f $user_pam_file && -r $user_pam_base ]] && same_text "$(user_pam_text)" "$user_pam_file"; then
    $sudo_cmd rm -f -- "$user_pam_file" || die "cannot remove $user_pam_file"
  elif [[ -f $user_pam_file ]]; then
    for pattern in "$pam_namespace_line" "$pam_exec_line"; do
      grep -Fxq "$pattern" "$user_pam_file" && $sudo_cmd sed -i "\\|^${pattern}\$|d" "$user_pam_file"
    done
  fi
  say "Left $guest's copies of your helper services and game rules in $guest_home/.config"
  for pattern in "$pam_auth_line" "$pam_namespace_line" "$pam_exec_line"; do
    grep -Fxq "$pattern" "$pam_file" 2>/dev/null || continue
    $sudo_cmd sed -i "\\|^${pattern}\$|d" "$pam_file" || die "cannot edit $pam_file"
  done
  systemctl is-active --quiet sshd && $sudo_cmd systemctl reload sshd
  if getent passwd "$guest" >/dev/null; then
    for tree in "$library" "$steam" "$games"; do
      [[ -d $root$tree ]] || continue
      $sudo_cmd setfacl -R -P -x "u:$guest" -- "$root$tree" 2>/dev/null
      $sudo_cmd find "$root$tree" -type d -print0 | $sudo_cmd xargs -0r setfacl -P -x "d:u:$guest" -- 2>/dev/null
    done
  fi
  say "Removed the guest session wrapper and $guest's access to $owner's Steam."
  say "The account and its prefixes remain: sudo userdel -r $guest; sudo rm -r $library_instances $home_instances"
}

check_component() {
  local failures=0 tree
  ok() { printf 'OK   steam-guest: %s\n' "$*"; }
  fail() { printf 'FAIL steam-guest: %s\n' "$*"; failures=$((failures + 1)); }

  if getent passwd "$guest" >/dev/null; then
    ok "user $guest exists"
    user_groups | grep -Fxq "$group" && ok "$guest is in $group" || fail "$guest is not in $group"
    user_groups | grep -Fxq wheel && fail "$guest is in wheel and can use sudo" || ok "$guest has no sudo"
  else
    fail "user $guest does not exist"
  fi
  same "$session_src" "$session_dst" && same_text "$(config_text)" "$config_dst" \
    && ok "guest session wrapper installed" || fail "guest session wrapper missing or outdated"
  same "$profile_src" "$profile_dst" && ok "$group logins are forced into Steam" \
    || fail "login hook missing or outdated: ${profile_dst#"$root"}"
  same "$view_src" "$view_dst" && grep -Fxq "$pam_namespace_line" "$pam_file" 2>/dev/null \
    && grep -Fxq "$pam_exec_line" "$pam_file" 2>/dev/null && ok "shared Steam view enabled in ${pam_file#"$root"}" \
    || fail "shared Steam view missing from ${pam_file#"$root"} or outdated"
  first_auth_is_ours "$pam_file" && ok "$guest logs in without a password" \
    || fail "passwordless login missing from ${pam_file#"$root"}"
  if [[ -f $lock_pam_file ]]; then
    first_auth_is_ours "$lock_pam_file" && ok "$guest unlocks the lock screen without a password" \
      || fail "passwordless unlock missing from ${lock_pam_file#"$root"} (omarchy-apply-lock rewrites it; rerun install)"
  fi
  same_text "$(namespace_text)" "$namespace_dst" \
    && [[ $(stat -c %a:%U "$root$library_instances" 2>/dev/null) == 0:root ]] \
    && [[ $(stat -c %a:%U "$root$home_instances" 2>/dev/null) == 0:root ]] \
    && ok "private Proton prefixes configured" || fail "private Proton prefixes not configured"
  if [[ -r $user_pam_base ]]; then
    same_text "$(user_pam_text)" "$user_pam_file" && ok "$guest's user manager sees the shared Steam" \
      || fail "${user_pam_file#"$root"} missing or out of date with ${user_pam_base#"$root"} (rerun install)"
  fi
  if [[ -d $root$guest_home && ! -r $root$guest_home ]]; then
    ok "$guest's home is private (Steam link checked by install)"
  elif [[ $(readlink -- "$root$guest_home/.local/share/Steam" 2>/dev/null) == "$steam" ]]; then
    ok "$guest uses $steam"
  else
    fail "$guest_home/.local/share/Steam does not point at $steam"
  fi
  if [[ -d $theme_base ]]; then
    theme_current && ok "login screen can pick $guest" || fail "user switcher theme missing or outdated: ${theme_dst#"$root"}"
  fi
  if [[ -d $root/etc/ssh/sshd_config.d ]]; then
    same_text "$(sshd_text)" "$sshd_dst" && ok "SSH denied to $group" || fail "SSH not denied to $group"
  fi
  for tree in "$steam" "$library" "$games"; do
    [[ -d $root$tree ]] || continue
    granted "$tree" && ok "$guest can use $tree" || fail "$guest has no ACLs on $tree"
  done
  return "$failures"
}

if [[ -z $guest ]]; then
  say "STEAM_GUEST_USER is empty; no Steam-only account is managed"
  exit 0
fi

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) die "unknown action '$action' (install|check|dry-run|uninstall)" ;;
esac
