#!/usr/bin/env bash
# Private payloads and account data must be ignored and never tracked.
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"

private=(
  delta-center-linux-compat-2.0.11-x64.tar.gz outputs/linux-unpacked/delta-center
  vendor/blob private/notes.txt pcsx2-Qt.AppImage
  "Content Manager.exe" ac-fonts.zip bios/SCPH-70012.bin
  roms/ps2/game.iso game.chd userdata/123/config/shortcuts.vdf
  shortcuts.vdf localconfig.vdf loginusers.vdf
  setup.log reports/doctor.txt backups/file config/machine.env
)
for path in "${private[@]}"; do
  git check-ignore -q --no-index -- "$path" || { echo "not ignored: $path" >&2; exit 1; }
done

# Versioned files that the patterns above must not swallow.
for path in systemd/user/delta-center.service config/machine.example.env setup.sh; do
  git check-ignore -q --no-index -- "$path" && { echo "wrongly ignored: $path" >&2; exit 1; }
done

# Neither the working tree nor any commit in history may contain them.
prohibited='\.(AppImage|tar\.gz|zip|exe|iso|chd|log)$|(^|/)(shortcuts|localconfig|loginusers)\.vdf$|(^|/)(roms|userdata|vendor|private|bios)/'
tracked=$( { git ls-files; git log --all --name-only --format=; } | sort -u | grep -E "$prohibited" || true)
[[ -z $tracked ]] || { printf 'private files are tracked or in history:\n%s\n' "$tracked" >&2; exit 1; }

echo 'Privacy ignore-rule test passed'
