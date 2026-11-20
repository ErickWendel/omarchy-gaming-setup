#!/usr/bin/env bash
set -euo pipefail

# Installs BackstageHero (background videos for Clone Hero / YARG songs) from
# source: AARP41298's fork, branch main-con-suppot, pinned to a reviewed
# commit. Its releases are Windows .exe only; the source runs on Linux with
# uv's Python (bundles Tk) and the system ffmpeg and libmpv.
#   install.sh          install or update to the pinned commit
#   install.sh check    report what is in place

repo_url=https://github.com/AARP41298/BackstageHero
commit=cc4843852ef1e2c1f18d0c8d0eb5e5aeb70cb2a3
python_version=3.12

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
app_dir="$data_home/omarchy-backstagehero"
src_dir="$app_dir/src"
venv_dir="$app_dir/venv"
launcher="$HOME/.local/bin/omarchy-backstagehero"
desktop_file="$data_home/applications/backstagehero.desktop"

check() {
  local rc=0
  [[ $(git -C "$src_dir" rev-parse HEAD 2>/dev/null) == "$commit" ]] &&
    echo "OK   source at ${commit:0:7} in $src_dir" || { echo "FAIL source missing or not at ${commit:0:7}"; rc=1; }
  "$venv_dir/bin/python" -c 'import tkinter, customtkinter, yt_dlp, numpy, mpv' 2>/dev/null &&
    echo "OK   Python environment (Tk, customtkinter, yt-dlp, numpy, mpv)" || { echo "FAIL Python environment incomplete"; rc=1; }
  command -v ffmpeg >/dev/null && echo "OK   ffmpeg" || { echo "FAIL ffmpeg not on PATH"; rc=1; }
  cmp -s "$component_dir/backstagehero-launch" "$launcher" &&
    echo "OK   $launcher" || { echo "FAIL $launcher missing or outdated"; rc=1; }
  [[ -f $desktop_file ]] && echo "OK   app menu entry" || { echo "FAIL no app menu entry"; rc=1; }
  return "$rc"
}

if [[ ${1:-} == check ]]; then
  check
  exit
fi

command -v uv >/dev/null || { echo "uv is needed (mise use -g uv)" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed (omarchy pkg add ffmpeg)" >&2; exit 1; }

mkdir -p -- "$app_dir"
if [[ ! -d $src_dir/.git ]]; then
  git clone -q "$repo_url" "$src_dir"
fi
git -C "$src_dir" fetch -q origin main-con-suppot
git -C "$src_dir" -c advice.detachedHead=false checkout -q "$commit"

[[ -x $venv_dir/bin/python ]] || uv venv -q --python "$python_version" "$venv_dir"
uv pip install -q --python "$venv_dir/bin/python" -r "$src_dir/requirements.txt"

install -Dm755 "$component_dir/backstagehero-launch" "$launcher"
mkdir -p -- "$(dirname -- "$desktop_file")"
cat >"$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=BackstageHero
Comment=Background videos for Clone Hero and YARG songs
Exec=$launcher
Icon=$src_dir/assets/icon.png
Categories=Game;AudioVideo;
Terminal=false
DESKTOP
check
