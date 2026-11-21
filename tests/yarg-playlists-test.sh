#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tool="$repo_dir/components/yarg/game-playlists.py"
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

song() { # dir chart-content [chart-file]
  mkdir -p "$root/$1"
  echo "[song]" >"$root/$1/song.ini"
  printf '%s' "$2" >"$root/$1/${3:-notes.mid}"
}
sha() { printf '%s' "$1" | sha1sum | cut -c1-40 | tr a-f A-F; }

lib="Songs/[GUITAR HERO]"
song "$lib/[GUITAR HERO III]/Quickplay/Slayer - Raining Blood" raining
song "$lib/[GUITAR HERO III]/Bonus/Dragonforce - TTFAF" ttfaf notes.chart
song "$lib/[GUITAR HERO III]/Tutorials/Tutorial 1" tutorial
song "$lib/[GUITAR HERO - DLC]/[GUITAR HERO III - DLC]/A Band - Song" dlc
song "$lib/[GUITAR HERO - DLC]/[GHWT - DLC]/Band - Song" wtdlc
song "Songs/[ROCK BAND]/[ROCK BAND 2]/01. Survivor - Eye of the Tiger" tiger
song "Kept/Metallica - One" one
song "Other/Legiao - Tempo Perdido" tempo; printf 'artist = Legião Urbana\nname = Tempo Perdido\n' >>"$root/Other/Legiao - Tempo Perdido/song.ini"
song "Other/Forro" forro; printf 'artist = Someone\ngenre = Forró\n' >>"$root/Other/Forro/song.ini"
song "Other/Joji - Samba" samba; printf 'artist = Joji\ngenre = Bossa Nova\n' >>"$root/Other/Joji - Samba/song.ini"
song "Other/With Video" vid; : >"$root/Other/With Video/video.mp4"
song "Other/Clean Video" cleanvid; : >"$root/Other/Clean Video/bg_clean.webm"
song "Other/Image Only" img; : >"$root/Other/Image Only/bg.png"
printf '%s\t%s\t%s\n' "$root/$lib/[GUITAR HERO III]/Quickplay/Metallica - One" "$root/dups/x" "$root/Kept/Metallica - One" >"$root/moved.tsv"

dest="$root/playlists"
mkdir -p "$dest"
echo '{"Name":"Mine","Author":"You","SongHashes":[]}' >"$dest/mine.json"
echo '{"Name":"Old","Author":"omarchy","SongHashes":[]}' >"$dest/omarchy - Old.json"

run() { python3 -I "$tool" --songs "$root/Songs" --moved "$root/moved.tsv" --library "$root/Other" --dest "$dest" "$@"; }
run --dry-run | grep -q "7 playlists, 16 songs" || fail "wrong plan: $(run --dry-run)"
[[ -f $dest/omarchy\ -\ Old.json ]] || fail "dry run wrote"
run >/dev/null

gh3="$dest/omarchy - Guitar Hero III.json"
[[ -f $gh3 && -f "$dest/omarchy - Guitar Hero World Tour.json" && -f "$dest/omarchy - Rock Band 2.json" ]] ||
  fail "playlists missing: $(ls "$dest")"
[[ -f $dest/mine.json ]] || fail "user playlist removed"
[[ ! -e "$dest/omarchy - Old.json" ]] || fail "stale omarchy playlist kept"
! ls "$dest" | grep -q DLC || fail "separate DLC playlist written: $(ls "$dest")"
python3 -I - "$gh3" "$(sha ttfaf)" "$(sha one)" "$(sha raining)" "$(sha dlc)" "$(sha tutorial)" <<'PY' || fail "wrong Guitar Hero III playlist: $(cat "$gh3")"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["Name"] == "Guitar Hero III" and d["Author"] == "omarchy"
assert d["SongHashes"] == sys.argv[2:6], d["SongHashes"]
assert d["Count"] == 4
PY
python3 -I - "$dest" "$(sha vid)" "$(sha cleanvid)" "$(sha forro)" "$(sha tempo)" <<'PY' || fail "wrong video/Brazilian playlists: $(cat "$dest"/omarchy\ -\ [MS]*)"
import json, sys
d = sys.argv[1]
videos = json.load(open(d + "/omarchy - Songs with Videos.json"))["SongHashes"]
brazil = json.load(open(d + "/omarchy - Músicas Nacionais.json", encoding="utf-8"))
assert sorted(videos) == sorted(sys.argv[2:4]), videos
assert brazil["Name"] == "Músicas Nacionais"
assert sorted(brazil["SongHashes"]) == sorted(sys.argv[4:6]), brazil["SongHashes"]
PY
python3 -I - "$dest" "$(sha ttfaf)" "$(sha one)" "$(sha raining)" "$(sha dlc)" "$(sha wtdlc)" "$(sha tiger)" <<'PY' || fail "wrong (All) playlists: $(ls "$dest")"
import json, sys
d, h = sys.argv[1], sys.argv[2:]
gh = json.load(open(d + "/omarchy - Guitar Hero (All).json"))
rb = json.load(open(d + "/omarchy - Rock Band (All).json"))
assert gh["Name"] == "Guitar Hero (All)" and gh["SongHashes"] == h[:4] + [h[4]], gh["SongHashes"]
assert rb["SongHashes"] == [h[5]], rb["SongHashes"]
PY
id1=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["Id"])' "$gh3")
run >/dev/null
id2=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["Id"])' "$gh3")
[[ $id1 == "$id2" ]] || fail "playlist id changed between runs"
echo "yarg-playlists-test: OK"
