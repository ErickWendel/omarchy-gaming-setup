# Members of steam-only get the Steam console session and nothing else.
# Every login (SDDM's wayland-session, a TTY) runs a login shell that reads
# /etc/profile before the user's own files, so whatever session was picked
# on the login screen is replaced by Steam here.
# Managed by omarchy-gaming-setup (components/steam-guest).
if [ -z "${OMARCHY_STEAM_SESSION-}" ] && id -nG 2>/dev/null | tr ' ' '\n' | grep -Fxq steam-only; then
  exec /usr/local/bin/omarchy-steam-session
fi
