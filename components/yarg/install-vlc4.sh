#!/usr/bin/env bash
set -euo pipefail

# Private libVLC 4 for YARG's song videos.
#
# YARG plays song videos through libVLC 4 (YARG_Data/Plugins/
# libVLCUnityPlugin.so needs libvlc.so.12). Arch ships VLC 3 (libvlc.so.5),
# and VLC 4 is unreleased, so this takes Chaotic-AUR's prebuilt vlc-git
# package, checks its signature against Chaotic-AUR's keyring (itself checked
# against the project key), and unpacks only the libraries and plugins into
# ~/.local/share/omarchy-yarg/vlc4. Nothing is installed system-wide and pacman
# is not touched; omarchy-yarg links YARG to it at start.
#   install-vlc4.sh          install or update to Chaotic-AUR's current build
#   install-vlc4.sh check    report what is in place

mirror=https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64
# Chaotic-AUR's project key (Pedro Henrique Lara Campos); signs chaotic-keyring.
project_key=EF925EA60F33D0CB85C44AD13056513887B78AEB
dest=${OMARCHY_YARG_VLC:-${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-yarg/vlc4}

check() {
  local rc=0 missing
  if [[ -f $dest/libvlc.so.12 && -f $dest/vlc/plugins/plugins.dat ]]; then
    echo "OK   libVLC 4 in $dest ($(cat "$dest/.version" 2>/dev/null || echo unknown version))"
  else
    echo "FAIL no libVLC 4 in $dest"; return 1
  fi
  for f in "$dest/libvlc.so.12" "$dest/libvlccore.so.9" \
           "$dest/vlc/plugins/codec/libavcodec_plugin.so" "$dest/vlc/plugins/demux/libmp4_plugin.so"; do
    missing=$(LD_LIBRARY_PATH=$dest:$dest/vlc ldd "$f" 2>/dev/null | awk '/not found/{print $1}' | tr '\n' ' ')
    [[ -z $missing ]] && echo "OK   $(basename "$f") links" || { echo "FAIL $(basename "$f") misses $missing"; rc=1; }
  done
  return "$rc"
}

if [[ ${1:-} == check ]]; then
  check
  exit
fi

for tool in curl gpg bsdtar; do
  command -v "$tool" >/dev/null || { echo "$tool is needed" >&2; exit 1; }
done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m700 "$GNUPGHOME"

curl -sSfL -o "$work/repo.db" "$mirror/chaotic-aur.db"
mkdir "$work/db"
bsdtar -xf "$work/repo.db" -C "$work/db"
pkg_file() { # name -> file name of its package in the repo db
  local desc
  desc=$(find "$work/db" -mindepth 2 -maxdepth 2 -path "*/$1-[0-9]*/desc" | head -1)
  [[ -n $desc ]] && sed -n '/^%FILENAME%$/{n;p;q}' "$desc"
}
keyring=$(pkg_file chaotic-keyring)
vlc=$(pkg_file vlc-git)
[[ -n $keyring && -n $vlc ]] || { echo "chaotic-keyring or vlc-git not in $mirror" >&2; exit 1; }

fetch() { curl -sSfL -o "$work/$1" "$mirror/$1" && curl -sSfL -o "$work/$1.sig" "$mirror/$1.sig"; }
verified() { # file -> 0 when signed by a key in $GNUPGHOME
  gpg --batch --status-fd 1 --verify "$work/$1.sig" "$work/$1" 2>/dev/null | grep -q '^\[GNUPG:\] VALIDSIG'
}

fetch "$keyring"
gpg --batch -q --keyserver hkps://keyserver.ubuntu.com --recv-keys "$project_key"
verified "$keyring" || { echo "$keyring: bad signature" >&2; exit 1; }
mkdir "$work/keyring"
bsdtar -xf "$work/$keyring" -C "$work/keyring"
gpg --batch -q --import "$work/keyring/usr/share/pacman/keyrings/chaotic.gpg"

fetch "$vlc"
verified "$vlc" || { echo "$vlc: bad signature" >&2; exit 1; }
# The signing key must belong to a key the keyring lists as trusted.
signer=$(gpg --batch --status-fd 1 --verify "$work/$vlc.sig" "$work/$vlc" 2>/dev/null |
  awk '$2 == "VALIDSIG" {print $NF}')
grep -q "^$signer:" "$work/keyring/usr/share/pacman/keyrings/chaotic-trusted" ||
  { echo "$vlc: signed by $signer, not a trusted Chaotic-AUR key" >&2; exit 1; }

staging="$dest.new"
[[ $staging == */omarchy-yarg/vlc4.new || -n ${OMARCHY_YARG_VLC:-} ]] || { echo "unexpected path $staging" >&2; exit 1; }
rm -rf -- "$staging"
mkdir -p -- "$staging"
bsdtar -xf "$work/$vlc" -C "$staging" --strip-components 2 usr/lib
LD_LIBRARY_PATH="$staging:$staging/vlc" "$staging/vlc/vlc-cache-gen" "$staging/vlc/plugins"
echo "${vlc%-x86_64.pkg.tar.zst}" >"$staging/.version"
if [[ -d $dest ]]; then
  mv -- "$dest" "$dest.old"
fi
mv -- "$staging" "$dest"
rm -rf -- "$dest.old"
check
