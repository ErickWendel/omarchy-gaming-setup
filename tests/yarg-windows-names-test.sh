#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tool="$repo_dir/components/yarg/windows-names.py"
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export XDG_STATE_HOME="$root/state"

lib="$root/lib"
mkdir -p "$lib/Alestorm/P.A.R.T.Y." "$lib/Album: One/Song?" "$lib/Fine" "$lib/Clash." "$lib/Clash" "$lib/trail "
touch "$lib/Album: One/Song?/song.ini" "$lib/Album: One/x*.rar" "$lib/Fine/song.ini"
python3 -I "$tool" "$lib" | grep -q "would rename 6 (1 already exist" || fail "dry run plan wrong: $(python3 -I "$tool" "$lib" | head -1)"
[[ -d "$lib/Album: One" ]] || fail "dry run renamed"
python3 -I "$tool" --apply "$lib" >/dev/null 2>&1 && fail "clash not reported in exit status"
[[ -d "$lib/Alestorm/P.A.R.T.Y" && -f "$lib/Album： One/Song？/song.ini" && -f "$lib/Album： One/x＊.rar" ]] || fail "not renamed"
[[ -d "$lib/trail" && -d "$lib/Clash." && -d "$lib/Fine" ]] || fail "trailing space not dropped, clash renamed, or good name touched"
python3 -I "$tool" --restore >/dev/null
[[ -f "$lib/Album: One/Song?/song.ini" && -d "$lib/Alestorm/P.A.R.T.Y." && -d "$lib/trail " ]] || fail "not restored"
echo "yarg-windows-names-test: OK"
