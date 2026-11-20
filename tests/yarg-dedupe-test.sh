#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tool="$repo_dir/components/yarg/dedupe-songs.py"
root=$(mktemp -d)
trap 'chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

song() { # dir artist name parts...
  local dir=$1 artist=$2 name=$3 p; shift 3
  mkdir -p "$root/lib/$dir"
  { echo "[song]"; echo "artist = $artist"; echo "name = $name"
    for p in "$@"; do echo "diff_$p = 3"; done; } >"$root/lib/$dir/song.ini"
  : >"$root/lib/$dir/notes.chart"
}
song "A/full" "Avenged Sevenfold" "A Little Piece of Heaven" guitar bass drums vocals
song "B/guitar" "avenged sevenfold" "A Little Piece Of Heaven" guitar
song "C/other" "The Band" "Song & Dance" guitar
song "D/other2" "Band" "Song and Dance" guitar bass
song "E/live" "Avenged Sevenfold" "A Little Piece of Heaven (Live)" guitar
song $'G/bad\x92name' "Band" "Song and Dance" guitar
song "H/track" "Iron Maiden" "5: Deja-Vu" guitar
song "H/full" "Iron Maiden" "Deja-Vu" guitar bass drums
song "H/acacia" "Iron Maiden" "22 Acacia Avenue" guitar bass
song "H/acacia2" "Iron Maiden" "Acacia Avenue" guitar
song "H/paren" "Band" "1) Song & Dance" guitar
song "H/tier" "Iron Maiden" "2. 22 Acacia Avenue" guitar
song "F/parent" "Band" "Song and Dance" guitar
song "F/parent/child" "Unique" "Only One" guitar

chmod a-w "$root/lib/C/other" "$root/lib/C"
run() { python3 -I "$tool" --base "$root" --dest "$root/dups" "$@"; }
run "$root/lib" | grep -q "14 charts, 6 duplicates" || fail "wrong plan: $(run "$root/lib")"
[[ -d $root/lib/B/guitar ]] || fail "dry run moved something"
run --apply "$root/lib" >/dev/null
[[ -d $root/lib/A/full && -d $root/lib/D/other2 && -d $root/lib/E/live ]] || fail "kept charts moved"
[[ -d $root/dups/lib/B/guitar && -d $root/dups/lib/C/other ]] || fail "duplicates not moved"
[[ -d $root/dups/lib/H/track && -d $root/lib/H/full && -d $root/lib/H/acacia && -d $root/lib/H/acacia2 ]] || fail "track-number title not matched, or a number title merged"
[[ -d $root/dups/lib/H/paren && -d $root/dups/lib/H/tier ]] || fail "1) or 2. track numbers not matched"
[[ -d $root/lib/F/parent/child ]] || fail "song folder holding another song was moved"
[[ $(wc -l <"$root/dups/moved.tsv") == 6 ]] || fail "restore list wrong"
python3 -I "$tool" --base "$root" --dest "$root/dups" "$root" 2>/dev/null && fail "dest inside folders accepted"
[[ $(stat -c %a "$root/lib/C") == 555 && $(stat -c %a "$root/dups/lib/C/other") == 555 ]] || fail "read-only modes not kept"
run --restore >/dev/null
[[ -d $root/lib/B/guitar && -d $root/lib/C/other && ! -d $root/dups/lib/B/guitar ]] || fail "restore failed"
echo "yarg-dedupe-test: OK"
