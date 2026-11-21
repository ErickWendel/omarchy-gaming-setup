#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
launcher="$repo_dir/components/yarg/yarg-launch"
configure="$repo_dir/components/yarg/configure_steam.py"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

me=$(id -un)
export OMARCHY_YARG_PLATFORM=linux
export OMARCHY_YARG_BACKEND=x11
export OMARCHY_YARG_VLC="$test_root/no-vlc"
export OMARCHY_YARG_DIR="$test_root/YARC"
songs="$OMARCHY_YARG_DIR/Songs"
shared="$OMARCHY_YARG_DIR/omarchy-shared-settings"
owner_cfg="$test_root/owner/release"
guest_cfg="$test_root/guest/release"
install_dir="$OMARCHY_YARG_DIR/YARG Installs/uuid-1/installation"
mkdir -p "$songs/Artist/Song" "$install_dir" "$owner_cfg/profiles" "$owner_cfg/scores"

# Fake YARG: records its working directory and arguments.
cat >"$install_dir/YARG" <<EOF
#!/usr/bin/env bash
echo "\$PWD \$*" >"$test_root/ran"
EOF
chmod +x "$install_dir/YARG"

[[ $("$launcher" --print-yarg) == "$install_dir/YARG" ]] || fail "YARG install not found"

# Owner run: song folder added to existing settings, settings published,
# scores not published.
echo '{"SongFolders": [], "VSync": true}' >"$owner_cfg/settings.json"
echo '{"bind": 1}' >"$owner_cfg/profiles/bindings.json"
echo score >"$owner_cfg/scores/scores.db"
OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher" -arg
[[ $(cat "$test_root/ran") == "$install_dir -download-location $OMARCHY_YARG_DIR -arg" ]] || fail "YARG not run from its folder with arguments"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["SongFolders"]==[sys.argv[2]] and d["VSync"]' \
  "$owner_cfg/settings.json" "$songs" || fail "owner settings lack the song folder"
[[ -f $shared/settings.json && -f $shared/profiles/bindings.json ]] || fail "owner settings not published"
[[ ! -e $shared/scores ]] || fail "scores were published"

# Second owner run does not duplicate the song folder.
OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher"
python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1]))["SongFolders"]==[sys.argv[2]]' \
  "$owner_cfg/settings.json" "$songs" || fail "song folder duplicated"

# Guest run (launcher owned by someone else): takes the shared settings.
OMARCHY_YARG_OWNER=someone-else OMARCHY_YARG_CONFIG=$guest_cfg "$launcher"
[[ -f $guest_cfg/profiles/bindings.json ]] || fail "guest did not take shared profiles"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["SongFolders"]==[sys.argv[2]] and d["VSync"]' \
  "$guest_cfg/settings.json" "$songs" || fail "guest settings wrong"

# Guest without shared settings still gets the song folder.
rm -rf -- "$shared" "$guest_cfg"
OMARCHY_YARG_OWNER=someone-else OMARCHY_YARG_CONFIG=$guest_cfg "$launcher"
python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1]))["SongFolders"]==[sys.argv[2]]' \
  "$guest_cfg/settings.json" "$songs" || fail "fresh guest has no song folder"

# Exit status of YARG is passed through.
printf '#!/bin/sh\nexit 3\n' >"$install_dir/YARG"
status=0; OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher" || status=$?
[[ $status == 3 ]] || fail "exit status not passed through ($status)"

# Wayland backend: added under a Wayland session or on request, never twice.
printf '#!/usr/bin/env bash\necho "$*" >"%s"\n' "$test_root/ran" >"$install_dir/YARG"
mkdir -p "$test_root/bin"
cat >"$test_root/bin/hyprctl" <<'EOF2'
#!/bin/sh
echo '[{"id":1,"name":"DP-1","width":3440,"height":1440},{"id":0,"name":"HDMI-A-1","width":1920,"height":1080}]'
EOF2
chmod +x "$test_root/bin/hyprctl"
loc="-download-location $OMARCHY_YARG_DIR"
wl() { PATH="$test_root/bin:$PATH" OMARCHY_YARG_BACKEND=auto WAYLAND_DISPLAY=wayland-9 OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher" "$@"; }
wl -x
[[ $(cat "$test_root/ran") == "-force-wayland -force-glcore -monitor 2 $loc -x" ]] || fail "Wayland backend/largest monitor not chosen: $(cat "$test_root/ran")"
OMARCHY_YARG_MONITOR=HDMI-A-1 wl
[[ $(cat "$test_root/ran") == "-force-wayland -force-glcore -monitor 1 $loc" ]] || fail "named monitor not chosen: $(cat "$test_root/ran")"
OMARCHY_YARG_MONITOR=nope wl
[[ $(cat "$test_root/ran") == "-force-wayland -force-glcore $loc" ]] || fail "unknown monitor not ignored"
wl -monitor 1
[[ $(cat "$test_root/ran") == "-force-wayland -force-glcore $loc -monitor 1" ]] || fail "user -monitor not respected"
OMARCHY_YARG_BACKEND=auto WAYLAND_DISPLAY= OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher" -x
[[ $(cat "$test_root/ran") == "$loc -x" ]] || fail "Wayland forced without a Wayland session"
OMARCHY_YARG_BACKEND=wayland OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher" -force-x11
[[ $(cat "$test_root/ran") == "$loc -force-x11" ]] || fail "-force-x11 not respected"

# No install: clear error.
YARG_BIN="$test_root/missing" "$launcher" 2>"$test_root/err" && fail "ran without YARG"
grep -q 'no YARG install' "$test_root/err" || fail "missing YARG not reported"

# Steam shortcut: added once, keeps existing entries, backed up.
if python3 -I -c 'import vdf' 2>/dev/null; then
  vdf_file="$test_root/shortcuts.vdf"
  python3 -I -c 'import vdf,sys; vdf.binary_dump({"shortcuts": {"0": {"appname": "Other", "exe": "\"/x\""}}}, open(sys.argv[1], "wb"))' "$vdf_file"
  exe="$test_root/home/.local/bin/omarchy-yarg"
  python3 -I "$configure" --check --shortcuts "$vdf_file" --exe "$exe" --backup-dir "$test_root/bak" && fail "check passed before install"
  python3 -I "$configure" --shortcuts "$vdf_file" --exe "$exe" --backup-dir "$test_root/bak" | grep -q 'Shortcut YARG' || fail "shortcut not written"
  python3 -I "$configure" --check --shortcuts "$vdf_file" --exe "$exe" --backup-dir "$test_root/bak" || fail "check fails after install"
  python3 -I "$configure" --shortcuts "$vdf_file" --exe "$exe" --backup-dir "$test_root/bak" | grep -q 'already up to date' || fail "shortcut rewritten"
  python3 -I -c 'import vdf,sys; s=vdf.binary_load(open(sys.argv[1],"rb"))["shortcuts"]; assert len(s)==2 and s["0"]["appname"]=="Other" and s["1"]["StartDir"].endswith("/bin/")' \
    "$vdf_file" || fail "shortcuts.vdf content wrong"
  [[ $(find "$test_root/bak" -name shortcuts.vdf | wc -l) == 1 ]] || fail "no single backup"
  appid=$(python3 -I "$configure" --print-appid --shortcuts "$vdf_file" --exe "$exe" --backup-dir "$test_root/bak")
  [[ $appid =~ ^[0-9]+$ ]] && ((appid >= 2147483648)) || fail "bad appid $appid"
  python3 -I "$configure" --shortcuts "$vdf_file" --exe "$exe" --backup-dir "$test_root/bak" --icon "/g/${appid}_icon.png" >/dev/null
  python3 -I -c 'import vdf,sys; s=vdf.binary_load(open(sys.argv[1],"rb"))["shortcuts"]; assert s["1"]["icon"]==sys.argv[2]' \
    "$vdf_file" "/g/${appid}_icon.png" || fail "icon not set"
else
  echo "SKIP: python vdf module not installed"
fi


# YARC downloads (venues, setlists): -download-location unless given.
OMARCHY_YARG_BACKEND=x11 OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher" -download-location /elsewhere
[[ $(cat "$test_root/ran") == "-download-location /elsewhere" ]] || fail "user -download-location not respected"

# xdg-open wrapper first on YARG's PATH drops Steam's LD_PRELOAD.
printf '#!/usr/bin/env bash\nhead -2 "$(command -v xdg-open)" | tail -1 >"%s"\n' "$test_root/ran" >"$install_dir/YARG"
if command -v xdg-open >/dev/null; then
  XDG_RUNTIME_DIR=$test_root OMARCHY_YARG_BACKEND=x11 OMARCHY_YARG_OWNER=$me OMARCHY_YARG_CONFIG=$owner_cfg "$launcher"
  [[ $(cat "$test_root/ran") == "unset LD_PRELOAD" ]] || fail "xdg-open wrapper not first on PATH"
fi
# Channel: nightly (tag bNNNN) by default, stable on request; separate
# settings folders, nightly seeded once from stable for the owner.
yi="$OMARCHY_YARG_DIR/YARG Installs"
mkdir -p "$yi/st/installation" "$yi/nt/installation"
echo v0.15.0 >"$yi/st/tag.txt"; echo b4164 >"$yi/nt/tag.txt"
for d in st nt; do printf '#!/usr/bin/env bash\necho "%s $PWD" >"%s"\n' "$d" "$test_root/ran" >"$yi/$d/installation/YARG"; chmod +x "$yi/$d/installation/YARG"; done
touch -d '2 days ago' "$yi/nt/installation/YARG"
[[ $("$launcher" --print-yarg) == "$yi/nt/installation/YARG" ]] || fail "nightly not preferred"
[[ $(OMARCHY_YARG_CHANNEL=stable "$launcher" --print-yarg) == "$yi/st/installation/YARG" ]] || fail "stable not chosen"
home="$test_root/home"; mkdir -p "$home/unity3d/YARC/YARG/release/profiles"
echo '{"SongFolders": ["/s"]}' >"$home/unity3d/YARC/YARG/release/settings.json"
echo '{}' >"$home/unity3d/YARC/YARG/release/profiles/p.json"
XDG_CONFIG_HOME=$home OMARCHY_YARG_BACKEND=x11 OMARCHY_YARG_OWNER=$me "$launcher"
[[ $(cut -d' ' -f1 "$test_root/ran") == nt ]] || fail "nightly not started"
[[ -f $home/unity3d/YARC/YARG/nightly/profiles/p.json ]] || fail "nightly not seeded from stable"
grep -q '"/s"' "$home/unity3d/YARC/YARG/nightly/settings.json" || fail "nightly settings lack stable song folders"
# Private VLC 4: plugins linked into the install, libraries on the path.
vlc="$test_root/vlc4"; mkdir -p "$vlc/vlc/plugins" "$yi/nt/installation/YARG_Data/Plugins"; : >"$vlc/libvlc.so.12"
printf '#!/usr/bin/env bash\necho "$LD_LIBRARY_PATH" >"%s"\n' "$test_root/ran" >"$yi/nt/installation/YARG"
OMARCHY_YARG_VLC_ENABLE=1 OMARCHY_YARG_VLC=$vlc XDG_CONFIG_HOME=$home OMARCHY_YARG_BACKEND=x11 OMARCHY_YARG_OWNER=$me "$launcher"
[[ $(readlink "$yi/nt/installation/YARG_Data/Plugins/vlc") == "$vlc/vlc" ]] || fail "VLC plugins not linked"
[[ $(cat "$test_root/ran") == "$vlc:$vlc/vlc"* ]] || fail "VLC libraries not on LD_LIBRARY_PATH"
OMARCHY_YARG_VLC=$vlc XDG_CONFIG_HOME=$home OMARCHY_YARG_BACKEND=x11 OMARCHY_YARG_OWNER=$me "$launcher"
[[ ! -e $yi/nt/installation/YARG_Data/Plugins/vlc ]] || fail "VLC link left when VLC is off"
[[ $(cat "$test_root/ran") != *"$vlc"* ]] || fail "VLC libraries on the path when VLC is off"
# Windows build under Proton (OMARCHY_YARG_PLATFORM=windows): newest Windows install
# of the channel, run through Proton with Wine paths, Wayland driver on and the
# largest monitor focused; first start seeded from the Linux settings without
# replacing what the Windows build already has.
wd="$test_root/win"; mkdir -p "$wd/b4100" "$wd/b4164" "$wd/v0.15.0"
for t in b4100 b4164 v0.15.0; do : >"$wd/$t/YARG.exe"; printf %s "$t" >"$wd/$t/tag.txt"; done
touch -d '2 days ago' "$wd/b4100/YARG.exe"
cat >"$test_root/proton" <<EOF2
#!/usr/bin/env bash
echo "\$PWD|\$*|\$STEAM_COMPAT_DATA_PATH|\${PROTON_ENABLE_WAYLAND:-}" >"$test_root/ran"
EOF2
chmod +x "$test_root/proton"
cat >"$test_root/bin/hyprctl" <<EOF2
#!/bin/sh
case "\$1" in
  -j) echo '[{"id":0,"name":"HDMI-A-1","width":1920,"height":1080,"x":3440,"y":0},{"id":1,"name":"DP-1","width":3440,"height":1440,"x":0,"y":0}]' ;;
esac
EOF2
win() { PATH="$test_root/bin:$PATH" OMARCHY_YARG_PLATFORM=windows OMARCHY_YARG_WINDOWS_DIR=$wd \
  OMARCHY_YARG_PROTON=$test_root/proton OMARCHY_YARG_PREFIX=$test_root/pfx XDG_CONFIG_HOME=$home \
  OMARCHY_YARG_OWNER=$me "$launcher" "$@"; }
[[ $(win --print-yarg) == "$wd/b4164/YARG.exe" ]] || fail "newest Windows nightly not chosen"
[[ $(OMARCHY_YARG_CHANNEL=stable win --print-yarg) == "$wd/v0.15.0/YARG.exe" ]] || fail "Windows stable not chosen"
wcfg="$test_root/pfx/pfx/drive_c/users/steamuser/AppData/LocalLow/YARC/YARG/nightly"
mkdir -p "$wcfg/profiles"; echo '{"crkd": 1}' >"$wcfg/profiles/p.json"
echo '{"SongFolders": ["/s", "/s"]}' >"$home/unity3d/YARC/YARG/nightly/settings.json"
WAYLAND_DISPLAY=wayland-9 win -x
[[ $(cat "$test_root/ran") == "$wd/b4164|run ./YARG.exe -monitor 1 -screen-width 3440 -screen-height 1440 -screen-fullscreen 1 -download-location Z:${OMARCHY_YARG_DIR//\//\\} -x|$test_root/pfx|1" ]] ||
  fail "Windows build not run through Proton on the largest monitor: $(cat "$test_root/ran")"
OMARCHY_YARG_MONITOR=HDMI-A-1 WAYLAND_DISPLAY=wayland-9 win
[[ $(cat "$test_root/ran") == *"run ./YARG.exe -monitor 2 -screen-width 1920 -screen-height 1080 -screen-fullscreen 1 "* ]] ||
  fail "named monitor not passed in Wine order: $(cat "$test_root/ran")"
WAYLAND_DISPLAY=wayland-9 win -monitor 2
[[ $(cat "$test_root/ran") == *"run ./YARG.exe -download-location "*" -monitor 2|"* ]] || fail "user -monitor not respected"
python3 -I -c 'import json,sys; f=json.load(open(sys.argv[1]))["SongFolders"]; assert f==["Z:\\s", "Z:"+sys.argv[2].replace("/","\\")], f' \
  "$wcfg/settings.json" "$songs" || fail "Windows settings lack Wine song folders"
grep -q crkd "$wcfg/profiles/p.json" || fail "Windows bindings replaced by Linux ones"
[[ -f $wcfg/custom || -d $wcfg/custom || ! -e $home/unity3d/YARC/YARG/nightly/custom ]] || fail "custom not seeded"
WAYLAND_DISPLAY= win
[[ $(cat "$test_root/ran") == *"|" ]] || fail "Wayland driver on without a Wayland session"
OMARCHY_YARG_WINDOWS_DIR=$test_root/none OMARCHY_YARG_PLATFORM=windows "$launcher" 2>"$test_root/err" && fail "ran without Windows YARG"
grep -q 'install-windows.sh' "$test_root/err" || fail "missing Windows YARG not reported"
echo "yarg-test: OK"
