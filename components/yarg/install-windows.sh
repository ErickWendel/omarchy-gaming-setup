#!/usr/bin/env bash
set -euo pipefail

# Installs the Windows build of YARG that omarchy-yarg runs under GE-Proton
# (it plays H.264 song videos and recognises the CRKD guitar; see README).
# The YARC launcher on Linux only installs Linux builds, so this fetches the
# Windows zip of the same release from YARC's GitHub into
# /wdblack_4TB/Games/YARC/omarchy-windows/<tag>/.
#
#   install-windows.sh [TAG]   TAG: bNNNN (Nightly) or vX.Y.Z (Stable);
#                              default: the newest Nightly the YARC launcher
#                              installed
#   install-windows.sh check

yarc_dir=${OMARCHY_YARG_DIR:-/wdblack_4TB/Games/YARC}
win_dir=${OMARCHY_YARG_WINDOWS_DIR:-$yarc_dir/omarchy-windows}

newest_linux_tag() {
  local f t best=-1 tag=''
  for f in "$yarc_dir/YARG Installs"/*/tag.txt; do
    [[ -f $f ]] || continue
    t=$(head -c 64 -- "$f")
    [[ $t =~ ^b[0-9]+$ ]] || continue
    ((${t#b} > best)) && { best=${t#b}; tag=$t; }
  done
  printf '%s\n' "$tag"
}

if [[ ${1:-} == check ]]; then
  tag=$(newest_linux_tag)
  if [[ -f $win_dir/$tag/YARG.exe ]]; then
    echo "OK   Windows YARG $tag in $win_dir/$tag"
  else
    echo "FAIL no Windows YARG ${tag:-?} in $win_dir (run install-windows.sh)"
    exit 1
  fi
  exit
fi

tag=${1:-$(newest_linux_tag)}
[[ $tag =~ ^(b[0-9]+|v[0-9]+\.[0-9]+\.[0-9]+)$ ]] || { echo "install-windows.sh: no usable tag (${tag:-none})" >&2; exit 1; }
dest=$win_dir/$tag
if [[ -f $dest/YARG.exe ]]; then
  echo "Windows YARG $tag already in $dest"
  exit
fi
case $tag in
  b*) url="https://github.com/YARC-Official/YARG-BleedingEdge/releases/download/$tag/YARG_$tag-Windows-x64.zip" ;;
  *) url="https://github.com/YARC-Official/YARG/releases/download/$tag/YARG_$tag-Windows-x64.zip" ;;
esac

work=$(mktemp -d -p "$win_dir" ".install-$tag.XXXXXX" 2>/dev/null || { mkdir -p -- "$win_dir" && mktemp -d -p "$win_dir" ".install-$tag.XXXXXX"; })
trap 'rm -rf -- "$work"' EXIT
echo "Downloading $url"
curl -fL --progress-bar -o "$work/yarg.zip" "$url"
mkdir -- "$work/unpacked"
bsdtar -xf "$work/yarg.zip" -C "$work/unpacked"
[[ -f $work/unpacked/YARG.exe ]] || { echo "install-windows.sh: no YARG.exe in the zip" >&2; exit 1; }
printf '%s' "$tag" >"$work/unpacked/tag.txt"
mv -- "$work/unpacked" "$dest"
echo "Installed Windows YARG $tag in $dest"
