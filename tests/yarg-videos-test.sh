#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tool="$repo_dir/components/yarg/webm-videos.py"
root=$(mktemp -d)
trap 'chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export XDG_STATE_HOME="$root/state"
command -v ffmpeg >/dev/null || { echo "yarg-videos-test: skipped (no ffmpeg)"; exit 0; }

mk() { # dir codec-args...
  local d="$root/lib/$1"; shift
  mkdir -p "$d"; printf '[song]\nname = x\n' >"$d/song.ini"
  ffmpeg -nostdin -loglevel error -f lavfi -i testsrc=size=320x240:rate=10:duration=1 "$@"
}
mk h264 -c:v libx264 "$root/lib/h264/video.mp4"
mk vp8 -c:v libvpx "$root/lib/vp8/video.webm"
mk bh -c:v libx264 "$root/lib/bh/video.mp4"
printf 'video_start_time = -7310\nbackstagehero_source = abc\n' >>"$root/lib/bh/song.ini"
mk ro -c:v libx264 "$root/lib/ro/video.mp4"; chmod a-w "$root/lib/ro"
printf 'video_start_time = -500\n' >>"$root/lib/h264/song.ini"

run() { python3 -I "$tool" "$@" "$root/lib"; }
run >/dev/null
for d in h264 bh ro; do
  [[ $(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 "$root/lib/$d/bg.webm") == vp8 ]] || fail "$d: no VP8 bg.webm"
done
[[ ! -e $root/lib/vp8/bg.webm ]] || fail "VP8 video converted again"
[[ $(stat -c %a "$root/lib/ro") == 555 ]] || fail "read-only folder mode not kept"
grep -q '^video_start_time = 7310$' "$root/lib/bh/song.ini" || fail "BackstageHero offset not negated"
grep -q '^omarchy_bh_video_start_time = -7310$' "$root/lib/bh/song.ini" || fail "BackstageHero offset not kept"
grep -q '^video_start_time = -500$' "$root/lib/h264/song.ini" || fail "non-BackstageHero offset changed"
run | grep -q "0 videos to encode" || fail "second run not idempotent"
grep -c "^video_start_time" "$root/lib/bh/song.ini" | grep -qx 1 || fail "offset duplicated"
python3 -I "$tool" --offsets backstagehero >/dev/null
grep -q '^video_start_time = -7310$' "$root/lib/bh/song.ini" || fail "BackstageHero offset not restored"
! grep -q omarchy_bh "$root/lib/bh/song.ini" || fail "saved offset not removed"
# BackstageHero re-synced while in its meaning: the new value is converted.
sed -i 's/^video_start_time = -7310$/video_start_time = -2000/' "$root/lib/bh/song.ini"
run >/dev/null
grep -q '^video_start_time = 2000$' "$root/lib/bh/song.ini" || fail "re-synced offset not converted"
# An untagged VP8 bg.webm (first version) next to its H.264 source is redone.
ffmpeg -nostdin -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=10:duration=1 -c:v libvpx "$root/lib/h264/bg.webm"
run >/dev/null
[[ $(ffprobe -v error -show_entries format_tags=comment -of csv=p=0 "$root/lib/h264/bg.webm") == omarchy-webm-v2 ]] || fail "old bg.webm not re-encoded"
echo "yarg-videos-test: OK"
