#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
component="$repo_dir/components/steam-guest"
script="$component/steam-guest.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
state="$test_root/state"
mkdir -p "$fake_bin" "$state"
fail() { echo "FAIL: $*" >&2; exit 1; }

fake() { local name=$1; shift; printf '%s\n' '#!/usr/bin/env bash' "$@" >"$fake_bin/$name"; /usr/bin/chmod +x "$fake_bin/$name"; }
# Accounts live in $STATE: passwd lists users, groups.<user> their groups.
fake getent 'f=$STATE/$1; [[ -f $f ]] && grep -qx -- "$2" "$f" && echo "$2:x:1001:1001::/home/$2:/usr/bin/bash"'
fake id 'u=${*: -1}; [[ $u == -nG ]] && u=$USER; f=$STATE/groups.$u; [[ -f $f ]] || exit 1; paste -sd" " "$f"'
fake groupadd 'echo "${*: -1}" >>"$STATE/group"'
fake useradd 'echo "${*: -1}" >>"$STATE/passwd"; printf "%s\n" "$4" >"$STATE/groups.${*: -1}"; echo "useradd $*" >>"$STATE/log"'
fake gpasswd 'if [[ $1 == -a ]]; then echo "$3" >>"$STATE/groups.$2"; else sed -i "/^$3\$/d" "$STATE/groups.$2"; fi; echo "gpasswd $*" >>"$STATE/log"'
fake setfacl 'echo "setfacl $*" >>"$STATE/acl"'
# A tree counts as granted once a default ACL was set on it.
fake getfacl 'grep -Eq -- " -d -m .* ${*: -1}( |\$)" "$STATE/acl" 2>/dev/null && printf "user:guest:rwx\ndefault:user:guest:rwx\n"; true'
fake systemctl 'echo "systemctl $*" >>"$STATE/log"; [[ $1 != is-active ]]'
fake uwsm 'echo "uwsm $*" >"$STATE/desktop"'
fake steam 'true'
fake logger 'true'
fake passwd 'echo "passwd $*" >>"$STATE/log"'
# Ownership changes need root; stat reports the instance parents as root's.
fake chown 'echo "chown $*" >>"$STATE/log"'
fake chmod 'echo "chmod $*" >>"$STATE/log"'
fake stat 'if [[ ${*: -1} == *.steam-guest-compatdata ]]; then grep -q "chmod 000 ${*: -1}\$" "$STATE/log" && echo 0:root; else exec /usr/bin/stat "$@"; fi'
# install without root: drop -o/-g ownership options.
fake install 'a=(); while (($#)); do case $1 in -o|-g) shift ;; *) a+=("$1") ;; esac; shift; done; exec /usr/bin/install "${a[@]}"'

export PATH="$fake_bin:$PATH" STATE="$state"
export STEAM_GUEST_SUDO= STEAM_GUEST_ROOT="$test_root/root"
export STEAM_LIBRARY=/games/SteamLibrary GAMES_DIR=/games/Games STEAM_SESSION_OUTPUT=DP-1
root=$STEAM_GUEST_ROOT
run() { HOME=/home/owner USER=owner "$script" "$@"; }
steam="$root/home/owner/.local/share/Steam"
mkdir -p "$root/games/SteamLibrary/steamapps/common/Game" "$root/games/SteamLibrary/steamapps/compatdata/1/pfx" \
  "$steam/steamapps/compatdata/2674037821/pfx" "$root/games/Games/NFSU2" "$root/home/guest" \
  "$root/etc/pam.d" "$root/etc/ssh/sshd_config.d" "$root/usr/share/sddm/themes/omarchy"
: >"$root/usr/share/sddm/themes/omarchy/logo.png"; : >"$root/usr/share/sddm/themes/omarchy/theme.conf"
echo save >"$root/games/SteamLibrary/steamapps/compatdata/1/pfx/save"
printf '%s\n' '#%PAM-1.0' 'auth include system-login' 'session include system-login' >"$root/etc/pam.d/sddm"
printf '%s\n' '#%PAM-1.0' 'auth required pam_unix.so' >"$root/etc/pam.d/omarchy-lock-password"
mkdir -p "$root/usr/lib/pam.d" "$root/home/owner/.config/systemd/user" "$root/home/owner/.config/hypr" \
  "$root/home/guest/.config/hypr"
printf '%s\n' 'session optional pam_systemd.so' >"$root/usr/lib/pam.d/systemd-user"
printf '%s\n' '[Service]' 'ExecStart=%h/.local/lib/omarchy-gaming-setup/fullscreen-restore' '[Install]' \
  'WantedBy=graphical-session.target' >"$root/home/owner/.config/systemd/user/fullscreen-restore.service"
echo 'o.window("steam_app_1", { fullscreen = true })' >"$root/home/owner/.config/hypr/gaming.lua"
echo 'require("default.hypr.omarchy")' >"$root/home/guest/.config/hypr/hyprland.lua"
# Left behind by the kiosk version; install removes it.
mkdir -p "$root/etc/omarchy-steam-guest"; : >"$root/etc/omarchy-steam-guest/hyprland.lua"

output=$(run check) && fail "check passed before installation"
grep -q 'user guest does not exist' <<<"$output" || fail "missing user not reported"
grep -q 'shared Steam view missing' <<<"$output" || fail "missing view not reported"

run dry-run >/dev/null
[[ ! -e $root/usr/local/bin/omarchy-steam-session && ! -e $state/passwd ]] || fail "dry-run changed the system"

# An existing account in wheel loses sudo; one with its own Steam install
# has it moved aside for the shared one.
echo guest >"$state/passwd"; printf '%s\n' guest wheel >"$state/groups.guest"
mkdir -p "$root/home/guest/.local/share/Steam"
output=$(run install) || fail "install failed: $output"
grep -q 'Removed guest from wheel' <<<"$output" || fail "wheel removal not reported"
grep -qx steam-only "$state/groups.guest" || fail "guest not added to steam-only"
grep -qx wheel "$state/groups.guest" && fail "guest still in wheel"
cmp -s "$component/omarchy-steam-session" "$root/usr/local/bin/omarchy-steam-session" || fail "session not installed"
cmp -s "$component/omarchy-steam-guest-view" "$root/usr/local/lib/omarchy-gaming-setup/omarchy-steam-guest-view" \
  || fail "view hook not installed"
cmp -s "$component/profile.sh" "$root/etc/profile.d/omarchy-steam-only.sh" || fail "login hook not installed"
conf="$root/etc/omarchy-steam-session.conf"
for line in STEAM_LIBRARY=/games/SteamLibrary STEAM_GAMES_DIR=/games/Games STEAM_SHARED_OWNER=owner \
            STEAM_SHARED_HOME=/home/owner STEAM_GUEST_HOME_INSTANCES=/home/.steam-guest-compatdata; do
  grep -qx "$line" "$conf" || fail "session config lacks $line"
done
grep -qx '/games/SteamLibrary/steamapps/compatdata /games/.steam-guest-compatdata/ user ~guest' \
  "$root/etc/security/namespace.d/omarchy-steam-guest.conf" || fail "namespace.conf line wrong"
[[ $(<"$root/games/.steam-guest-compatdata/guest/1/pfx/save") == save ]] || fail "library prefix not copied"
[[ -d $root/home/.steam-guest-compatdata/guest/2674037821/pfx ]] || fail "shortcut prefix not copied"
grep -q 'chown -R guest:guest .*/guest/1$' "$state/log" || fail "copied prefix not given to guest"
[[ $(readlink "$root/home/guest/.local/share/Steam") == /home/owner/.local/share/Steam ]] || fail "guest Steam not linked"
[[ -d $root/home/guest/.local/share/Steam.before-shared ]] || fail "guest's own Steam not moved aside"
pam="$root/etc/pam.d/sddm"
grep -qx 'session    optional    pam_namespace.so mount_private' "$pam" || fail "pam_namespace not added"
grep -qx 'session    optional    pam_exec.so quiet /usr/local/lib/omarchy-gaming-setup/omarchy-steam-guest-view' \
  "$pam" || fail "pam_exec not added"
(($(grep -n pam_exec "$pam" | cut -d: -f1) > $(grep -n pam_namespace "$pam" | cut -d: -f1))) \
  || fail "pam_exec must follow pam_namespace"
[[ $(grep -m1 '^auth' "$pam") == 'auth       sufficient  pam_succeed_if.so user ingroup steam-only quiet' ]] \
  || fail "passwordless auth line not first: $(grep -m1 '^auth' "$pam")"
grep -qx 'passwd -l guest' "$state/log" || fail "guest password not locked"
[[ $(grep -m1 '^auth' "$root/etc/pam.d/omarchy-lock-password") == 'auth       sufficient  pam_succeed_if.so user ingroup steam-only quiet' ]] \
  || fail "lock screen still needs a password"
[[ ! -e $root/etc/omarchy-steam-guest ]] || fail "kiosk config left behind"
grep -qx 'DenyGroups steam-only' "$root/etc/ssh/sshd_config.d/30-omarchy-steam-only.conf" || fail "SSH not blocked"
theme="$root/usr/share/sddm/themes/omarchy-gaming"
cmp -s "$component/sddm-theme/Main.qml" "$theme/Main.qml" || fail "user switcher theme not installed"
[[ $(readlink "$theme/logo.png") == /usr/share/sddm/themes/omarchy/logo.png ]] || fail "theme images not linked"
grep -qx 'Current=omarchy-gaming' "$root/etc/sddm.conf.d/zz-omarchy-gaming-theme.conf" || fail "theme not selected"
grep -qx 'User=' "$root/etc/sddm.conf.d/zz-omarchy-gaming-theme.conf" || fail "autologin not turned off"
STEAM_GUEST_LOGIN_AT_BOOT=0 run install >/dev/null
grep -q 'Autologin' "$root/etc/sddm.conf.d/zz-omarchy-gaming-theme.conf" && fail "STEAM_GUEST_LOGIN_AT_BOOT=0 still overrides autologin"
run install >/dev/null
for tree in games/SteamLibrary home/owner/.local/share/Steam games/Games; do
  grep -q "setfacl -P -d -m u:guest:rwX,u:owner:rwX -- $root/$tree" "$state/acl" || fail "no ACLs on $tree"
done
grep -q 'compatdata' "$state/acl" && fail "ACLs touched the owner's compatdata"
upam="$root/etc/pam.d/systemd-user"
grep -qx 'session optional pam_systemd.so' "$upam" && grep -qx 'session    optional    pam_namespace.so mount_private' "$upam" \
  && grep -q 'pam_exec.so quiet /usr/local/lib/omarchy-gaming-setup/omarchy-steam-guest-view' "$upam" \
  || fail "user manager PAM stack lacks systemd's lines or the view"
gunits="$root/home/guest/.config/systemd/user"
grep -qx 'ExecStart=/home/owner/.local/lib/omarchy-gaming-setup/fullscreen-restore' "$gunits/fullscreen-restore.service" \
  || fail "helper unit not copied with the owner's paths"
[[ $(readlink "$gunits/graphical-session.target.wants/fullscreen-restore.service") == ../fullscreen-restore.service ]] \
  || fail "helper unit not enabled for the guest"
cmp -s "$root/home/owner/.config/hypr/gaming.lua" "$root/home/guest/.config/hypr/gaming.lua" || fail "game rules not copied"
grep -qx 'require("hypr.gaming")' "$root/home/guest/.config/hypr/hyprland.lua" || fail "game rules not required"
grep -Fqx 'STEAM_SHARED_RO_PATHS=.local/bin\ .local/lib/omarchy-gaming-setup\ .local/opt/delta-center' "$conf" \
  || fail "read-only helper paths missing from the session config"

output=$(run check) || fail "check failed after install: $output"
echo changed >"$root/games/SteamLibrary/steamapps/compatdata/1/pfx/save"
run install >/dev/null
[[ $(<"$root/games/.steam-guest-compatdata/guest/1/pfx/save") == save ]] || fail "reinstall overwrote the guest's prefix"
[[ $(grep -c 'require("hypr.gaming")' "$root/home/guest/.config/hypr/hyprland.lua") == 1 ]] || fail "reinstall duplicated the require"
[[ $(grep -c pam_namespace "$pam") == 1 && $(grep -c pam_exec "$pam") == 1 && $(grep -c pam_succeed_if "$pam") == 1 ]] || fail "reinstall duplicated pam lines"
[[ $(grep -c -- ' -d -m ' "$state/acl") == 3 ]] || fail "reinstall walked the trees again"

# A fresh install creates the account without sudo.
rm -f "$state/passwd" "$state/groups.guest"
run install >/dev/null
grep -q 'useradd --create-home --shell /usr/bin/bash --groups steam-only' "$state/log" || fail "user not created"

# Session: refuses a shared compatdata or a running owner Steam, otherwise
# runs the Omarchy desktop with Steam's gamepad UI autostarted.
session="$component/omarchy-steam-session"
view="$test_root/view"
mkdir -p "$view/home/owner/.local/share/Steam/steamapps/compatdata" "$view/lib/steamapps/compatdata"
fake rev-lights 'echo started >"$STATE/helper"; sleep 30'
printf '%s\n' "STEAM_LIBRARY=$view/lib" STEAM_SESSION_OUTPUT=DP-1 STEAM_SHARED_OWNER=owner \
  "STEAM_SHARED_HOME=$view/home/owner" "STEAM_SESSION_HELPERS=$fake_bin/rev-lights" \
  STEAM_CLIENT_ARGS=-cef-disable-gpu-compositing >"$test_root/session.conf"
export OMARCHY_STEAM_SESSION_CONF="$test_root/session.conf" OMARCHY_STEAM_OWNER_WAIT=1
export XDG_CONFIG_HOME="$test_root/guest-config"
printf '%s\n' "$USER" steam-only >"$state/groups.$USER"
compat="$view/lib/steamapps/compatdata"
# A dangling symlink stands in for a compatdata owned by someone else.
rmdir "$compat"; ln -s /nonexistent "$compat"
"$session" 2>/dev/null && fail "session started without a private compatdata"
rm "$compat"; mkdir "$compat"
fake pgrep '[[ -e $STATE/owner-steam ]]'
: >"$state/owner-steam"
"$session" 2>/dev/null && fail "session started while the owner's Steam runs"
rm "$state/owner-steam"
"$session" || fail "session did not start"
[[ $(<"$state/desktop") == "uwsm start -g -1 -e -D Hyprland hyprland.desktop" ]] \
  || fail "desktop command: $(<"$state/desktop")"
grep -qx 'Exec=steam -gamepadui -cef-disable-gpu-compositing' "$XDG_CONFIG_HOME/autostart/omarchy-steam-guest.desktop" \
  || fail "Steam Big Picture not autostarted"
[[ -e $state/helper ]] || fail "session helper not started"

# View hook: in a private mount namespace the owner's home shows only
# .local/bin (read-only) and Steam, with the guest's compatdata over Steam's.
hook="$component/omarchy-steam-guest-view"
owner_home="$view/home/owner"
mkdir -p "$owner_home/.local/bin" "$owner_home/.local/lib/omarchy-gaming-setup" "$owner_home/Documents" \
  "$test_root/instances/guest/2674037821" "$test_root/stash"
echo helper >"$owner_home/.local/lib/omarchy-gaming-setup/fullscreen-restore"
echo wrapper >"$owner_home/.local/bin/nfsu2-wheel-wrapper"
echo secret >"$owner_home/Documents/private"
printf '%s\n' "STEAM_SHARED_OWNER=owner" "STEAM_SHARED_HOME=$owner_home" \
  "STEAM_GUEST_HOME_INSTANCES=$test_root/instances" "STEAM_LIBRARY=$view/lib" \
  "STEAM_SHARED_RO_PATHS='.local/bin .local/lib/omarchy-gaming-setup .local/opt/missing'" >"$test_root/view.conf"
printf '%s\n' guest steam-only >"$state/groups.guest"
export OMARCHY_STEAM_SESSION_CONF="$test_root/view.conf" OMARCHY_STEAM_GUEST_STASH="$test_root/stash"
# The test's own namespace stands in for PID 1's.
export OMARCHY_STEAM_HOST_NS=/proc/$$/ns/mnt
PAM_TYPE=open_session PAM_USER=guest "$hook" 2>/dev/null && fail "view hook ran in the main mount namespace"
[[ -e $owner_home/Documents/private ]] || fail "view hook touched the main namespace"
PAM_TYPE=close_session PAM_USER=guest "$hook" || fail "close_session must be a no-op"
printf '%s\n' owner >"$state/groups.owner"
PAM_TYPE=open_session PAM_USER=owner "$hook" || fail "non steam-only users must be skipped"
seen=$(PAM_TYPE=open_session PAM_USER=guest unshare -rm --propagation private bash -c '
  "$1" >/dev/null 2>"$3" || { echo hook-failed; exit; }
  ls -A "$2"; ls -A "$2/.local"
  cat "$2/.local/bin/nfsu2-wheel-wrapper" "$2/.local/lib/omarchy-gaming-setup/fullscreen-restore"
  touch "$2/.local/lib/omarchy-gaming-setup/x" 2>/dev/null && echo lib-writable
  touch "$2/.local/bin/x" 2>/dev/null && echo bin-writable
  ls "$2/.local/share/Steam/steamapps/compatdata"' _ "$hook" "$owner_home" "$test_root/hook.err")
[[ $(paste -sd' ' <<<"$seen") == ".local bin lib share wrapper helper 2674037821" ]] || fail "guest view: $(paste -sd' ' <<<"$seen") $(cat "$test_root/hook.err")"
[[ -e $owner_home/Documents/private && -z $(ls -A "$owner_home/.local/share/Steam/steamapps/compatdata") ]] \
  || fail "view mounts leaked out of the namespace"
[[ -z $(ls -A "$test_root/stash") ]] || fail "view hook left its stash behind: $(cat "$test_root/hook.err")"

# Uninstall removes the hooks and the guest's ACLs but keeps the account.
run uninstall >/dev/null
[[ ! -e $root/etc/profile.d/omarchy-steam-only.sh && ! -e $root/usr/local/bin/omarchy-steam-session ]] \
  || fail "uninstall left files"
grep -q 'pam_namespace\|pam_exec\|pam_succeed_if' "$pam" && fail "uninstall left pam lines"
grep -q pam_succeed_if "$root/etc/pam.d/omarchy-lock-password" && fail "uninstall left the lock screen rule"
[[ ! -e $upam ]] || fail "uninstall left the generated user manager PAM file"
grep -qx 'auth include system-login' "$pam" || fail "uninstall removed the original auth line"
[[ ! -e $theme && ! -e $root/etc/sddm.conf.d/zz-omarchy-gaming-theme.conf ]] || fail "uninstall left the theme"
grep -q "setfacl -R -P -x u:guest -- $steam" "$state/acl" || fail "uninstall left ACLs"
grep -qx guest "$state/passwd" || fail "uninstall deleted the account"
echo "steam-guest tests passed"
