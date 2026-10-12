# Shared helpers for component scripts. Source after defining say() and die().
# shellcheck shell=bash

backup_root=${OMARCHY_BACKUP_ROOT:-$HOME/.local/state/omarchy-gaming-setup/backups}
# Suffix used by earlier releases when disabling an autostart entry in place.
legacy_disabled_suffix=.disabled-by-omarchy-gaming-setup

# Copy a file below $backup_root, mirroring its path relative to $HOME. The
# first backup wins so repeated runs never overwrite the original.
backup_once() {
  local source=$1 relative=${1#"$HOME"/} destination
  [[ -e "$source" || -L "$source" ]] || return 0
  destination="$backup_root/$relative"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  mkdir -p -- "$(dirname -- "$destination")" || \
    die "failed to create backup directory for $source"
  cp -a -- "$source" "$destination" || \
    die "failed to back up $source to $destination"
  say "Backed up $source to $destination"
}

# Back up and remove an XDG autostart entry, including a copy renamed in place
# by an earlier release. systemd-xdg-autostart-generator reads every file in
# ~/.config/autostart regardless of its suffix, so a renamed entry still
# launches at login; disabled entries must leave that directory entirely.
retire_autostart_entry() {
  local entry path destination
  for entry in "$1" "$1$legacy_disabled_suffix"; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    destination="$backup_root/${entry#"$HOME"/}"
    if [[ -e "$destination" || -L "$destination" ]] && ! cmp -s -- "$entry" "$destination"; then
      # Keep a recreated entry that differs from the first backup as well.
      path="$destination.$(date +%Y%m%d%H%M%S)"
      mkdir -p -- "$(dirname -- "$path")" && cp -a -- "$entry" "$path" || \
        die "failed to back up $entry to $path"
      say "Backed up $entry to $path"
    else
      backup_once "$entry"
    fi
    unlink -- "$entry" || die "failed to remove autostart entry $entry"
    say "Removed autostart entry $entry"
  done
}

graphical_session_active() {
  [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && \
    systemctl --user is-active --quiet graphical-session.target
}
