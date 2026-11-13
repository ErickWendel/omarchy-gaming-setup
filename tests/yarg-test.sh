#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
launcher="$repo_dir/components/yarg/yarg-launch"
configure="$repo_dir/components/yarg/configure_steam.py"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

me=$(id -un)
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
[[ $(cat "$test_root/ran") == "$install_dir -arg" ]] || fail "YARG not run from its folder with arguments"
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

echo "yarg-test: OK"
