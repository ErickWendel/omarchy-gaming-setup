# Steam guest account

A Linux account (`STEAM_GUEST_USER`, default `guest`) with a clean Omarchy
desktop of its own that plays games on **your** Steam install. It has no
password, no sudo and no SSH, and sees nothing of your home beyond Steam.
Steam's gamepad UI (Big Picture) opens at login; audio, monitors and the rest
of Omarchy work as usual. Log out from Omarchy's menu as on any account.

There is one Steam to maintain. The guest gets your Steam login, settings,
launch options, non-Steam shortcuts (NFS, F1 2020, FIFA Mod Manager),
Protons and Steam Input layouts as they are, plus copies of your Proton
prefixes, so wheel bindings, mods and saves carry over.

Run it as yourself (not root); it asks for sudo:

```bash
./components/steam-guest/steam-guest.sh install
```

Then log out, press ↓ (or Tab) on the login screen until it shows
`Steam guest`, and press Enter. The guest has no password.

## What the guest can do with your account

- It is signed in to **your Steam account**, so it can buy with your saved
  payment method. Set a Steam Family View PIN if that matters.
- It can write to the Steam client files you also run, so code it runs could
  end up running as you the next time you start Steam.
- Only one of you can run Steam at a time. Logging out stops your Steam (it
  runs in your session's `app-graphical.slice`); the guest session waits up
  to 20 seconds for it to exit and refuses to start if it is still running.
  Don't start yours while the guest is logged in (switch user).

## How it works

| Piece | Where | What it does |
| --- | --- | --- |
| Group `steam-only` | `/etc/group` | Marks accounts that use the owner's Steam (the name predates the full desktop). The account is removed from `wheel`. |
| No password | first `auth` line of `/etc/pam.d/sddm` and `/etc/pam.d/omarchy-lock-password`: `pam_succeed_if.so user ingroup steam-only` | The login screen and Omarchy's lock screen let `steam-only` members in with an empty password. The account's own password is locked (`passwd -l`), so TTY, `su` and SSH logins still fail. `omarchy-apply-lock` rewrites the lock-screen file; `check` reports it and install puts the line back. |
| Login hook | `/etc/profile.d/omarchy-steam-only.sh` | SDDM's `wayland-session` and TTY logins start a login shell, which reads `/etc/profile` before any user file. For `steam-only` members the hook runs the session wrapper instead. |
| Session wrapper | `/usr/local/bin/omarchy-steam-session` | Checks the shared Steam view, waits for your Steam to exit, writes `~/.config/autostart/omarchy-steam-guest.desktop` (`steam -gamepadui $STEAM_CLIENT_ARGS`) and runs Omarchy's own session (`uwsm start … hyprland.desktop`). It also starts `STEAM_SESSION_HELPERS` (the F1 2020 rev-light bridge) and afterwards gives you read/write on files the guest's Steam created. The desktop config is Omarchy's defaults from `/etc/skel`, finished by Omarchy's first-login setup. Earlier gamescope and kiosk-Hyprland versions were dropped: gamescope corrupted the screen on the RTX 5070, and the kiosk left no way to switch audio or monitors. |
| Your helpers and game rules | `~guest/.config/systemd/user`, `~guest/.config/hypr` | Install copies your `STEAM_GUEST_USER_UNITS` (fullscreen restore, PS button helper, F1 2020 rev lights, OpenRGB, Delta Center) with `%h` replaced by your home, enables them, and copies your `STEAM_GUEST_HYPR_RULES` (`gaming.lua`, `assettocorsa.lua`) with `require` lines in the guest's `hyprland.lua`. Rerun install after you change yours. Delta Center keeps its own settings per user. |
| Shared Steam view | `pam_exec` hook `/usr/local/lib/omarchy-gaming-setup/omarchy-steam-guest-view` in `/etc/pam.d/sddm` and `/etc/pam.d/systemd-user` | Your launch options, shortcuts and helper services name paths in `/home/erickwendel`. For the guest only, that path becomes an empty tmpfs holding `.local/share/Steam` and, read-only, the paths in `STEAM_SHARED_RO_PATHS` (`.local/bin`, `.local/lib/omarchy-gaming-setup`, `.local/opt/delta-center`). Nothing else in your home is visible. `~guest/.local/share/Steam` links there. The hook also runs for the guest's systemd user manager, because Omarchy starts apps (Steam from autostart) and user services through it. `/etc/pam.d/systemd-user` is systemd's `/usr/lib/pam.d/systemd-user` plus the two lines; `check` flags it when systemd's file changes. |
| Private prefixes | `pam_namespace` (`/etc/security/namespace.d/omarchy-steam-guest.conf`) and the view hook | Wine exits with "not owned by you" on another user's prefix. The guest's own copies are mounted over both `steamapps/compatdata` folders: the library's from `/wdblack_4TB/.steam-guest-compatdata/guest`, Steam's (non-Steam shortcuts) from `/home/.steam-guest-compatdata/guest`. |
| ACLs | your Steam folder, `/wdblack_4TB/SteamLibrary`, `/wdblack_4TB/Games` | Both accounts get `rwX`, inherited by new files; `compatdata` is left out. Steam writes some files `0600`, so the view hook reopens yours at each guest login and the session reopens the guest's when it ends. |
| Login screen | `/usr/share/sddm/themes/omarchy-gaming`, selected by `/etc/sddm.conf.d/zz-omarchy-gaming-theme.conf` | Omarchy's SDDM theme only asks for the last user's password. This copy (same look, images linked from Omarchy's theme) adds a user line: ↑/↓, Tab or a click on ‹ › switches between you and the guest. The same file empties `[Autologin]`, overriding Omarchy's `autologin.conf`, so boot shows the user list; set `STEAM_GUEST_LOGIN_AT_BOOT=0` to keep autologin. |
| SSH | `/etc/ssh/sshd_config.d/30-omarchy-steam-only.conf` | `DenyGroups steam-only`: `ssh guest@host cmd` would skip the login hook. |

`pam_namespace` runs with `mount_private`, and the view hook refuses to
mount anything unless the session already has its own mount namespace, so
nothing changes in your session. Both PAM lines are `optional`: if either
fails, the guest session sees a shared `compatdata` and refuses to start
instead of breaking Proton games. TTY logins do not use the SDDM PAM stack
and end the same way.

### Prefixes

Install copies each of your prefixes the guest does not have yet (btrfs
reflink: no extra space until one side changes). From then on each side has
its own saves and settings. Rerun install to copy prefixes for games added
since; it never overwrites a prefix the guest already has. To give the guest
a fresh copy of one, delete it from the guest's folder with sudo and rerun.

### Not covered

- PCSX2 shortcuts: `omarchy-pcsx2` reads the AppImage and settings from the
  launching user's home (`~/Applications`, `~/.config/PCSX2`).
- The game rules need the guest's `~/.config/hypr/hyprland.lua`, which comes
  from `/etc/skel`; if it is missing, install skips them.

## Undo

```bash
./components/steam-guest/steam-guest.sh uninstall   # sudo; keeps the account
```

It removes the session wrapper, hooks, PAM lines, login theme, SSH rule and the guest's ACLs. The guest keeps its copies of your helper services and game rules. The
account and its prefixes stay until you delete them:

```bash
sudo userdel -r guest
```

```bash
sudo rm -r /wdblack_4TB/.steam-guest-compatdata /home/.steam-guest-compatdata
```
