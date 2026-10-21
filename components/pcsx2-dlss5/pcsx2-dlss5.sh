#!/usr/bin/env bash
# Windows PCSX2 2.8.1 under Proton with ReShade and the DLSSNR Linux add-on
# (DLSS 5 neural rendering): install|check|dry-run|uninstall. See README.md.
# install needs PCSX2 closed; check and dry-run change nothing.
set -uo pipefail

component_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$component_dir/../.." && pwd)
config_file="$repo_dir/config/machine.env"
[[ -f $config_file ]] || config_file="$repo_dir/config/machine.example.env"
# shellcheck source=../../config/machine.example.env
source "$config_file"

action=${1:-check}
steam_root=${PCSX2_DLSS5_STEAM_ROOT:-$HOME/.local/share/Steam}
pcsx2_dir=${PCSX2_DLSS5_DIR:-$HOME/Games/PCSX2-Windows}
compat_dir=${PCSX2_DLSS5_PREFIX:-$HOME/.local/share/omarchy-gaming-setup/prefixes/pcsx2-windows}
prefix="$compat_dir/pfx"
proton=${PCSX2_DLSS5_PROTON:-$steam_root/compatibilitytools.d/GE-Proton11-1/proton}
downloads=${PCSX2_DLSS5_DOWNLOADS:-$HOME/Downloads/pcsx2-windows}
dlssnr_dir=${PCSX2_DLSS5_DLSSNR_DIR:-$HOME/Downloads/dlssnr-linux}
# ReShade 6.8 (add-on build) and the DLSS 5 model come from the Pinnacle of
# View pack that components/nfsu2 also uses.
pinnacle_host=${PCSX2_DLSS5_PINNACLE_HOST:-$(find "$HOME/Downloads/nfsu2" -maxdepth 2 -type d -path '*PinancleofView*/host64' 2>/dev/null | sort | tail -1)}
# Microsoft's ucrtbase.dll, from the Assetto Corsa prefix (vcrun2019).
ucrtbase_src=${PCSX2_DLSS5_UCRTBASE:-$steam_root/steamapps/compatdata/244210/pfx/drive_c/windows/system32/ucrtbase.dll}
icu_src="$(dirname -- "$proton")/files/lib/wine/x86_64-windows/icu.dll"
bios_dir=${PCSX2_DLSS5_BIOS:-$GEXTENDED_MOUNT/Emulation/bios}
games_dir=${PCSX2_DLSS5_GAMES:-$GEXTENDED_MOUNT/Emulation/roms/ps2}
launcher_dst="$HOME/.local/bin/omarchy-pcsx2-dlss5"
process=${PCSX2_DLSS5_PROCESS:-pcsx2-qt.exe}
overrides_key='Software\\Wine\\DllOverrides'
overrides=(dxgi d3dcompiler_47 ucrtbase)

archive="$downloads/pcsx2-v2.8.1-windows-x64-Qt.7z"
# name|source|sha256 of the inputs that were tested together.
pinned=(
  "pcsx2-v2.8.1-windows-x64-Qt.7z|$archive|e953cb12355eb0f86cb4a95fac6d91a3a654efd209bfba0c3faaeeaceb7d6b49"
  "d3dcompiler_47.dll|$downloads/d3dcompiler_47.dll|4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3"
  "dlssnr-linux.addon64|$dlssnr_dir/dlssnr-linux.addon64|5bacf247e5236164dc67d97e6fed89aa0a073978d629861a896b23259a648f21"
  "nvngx.dll_nrfwd.dll|$dlssnr_dir/nvngx.dll_nrfwd.dll|8b9c518b13da25311b9982114961acbb1f2b98828843740817073a6bcae809dd"
  "dxgi.dll|$pinnacle_host/dxgi.dll|0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7"
  "nvngx_dlssnr.dll|$pinnacle_host/nvngx_dlssnr.dll|8270b350cd82de5ce89806872cdd6b6a9249b80836b91bbeb3573470744cc206"
)
immerse_dir=${PCSX2_DLSS5_IMMERSE:-$downloads/iMMERSE}
immerse_files=(Shaders/MartysMods_LAUNCHPAD.fx Shaders/MartysMods/mmx_global.fxh Textures/iMMERSE_bluenoise_opt.png)

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN pcsx2-dlss5: %s\n' "$*" >&2; }
sha() { sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1; }
running() { pgrep -x "$process" >/dev/null 2>&1; }
# reg_has FILE KEY LINE: LINE is inside [KEY] of a Wine registry file.
reg_has() {
  REG_KEY="[$2]" REG_LINE="$3" awk '
    BEGIN { key = ENVIRON["REG_KEY"]; line = ENVIRON["REG_LINE"] }
    index($0, key) == 1 { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && $0 == line { found = 1 }
    END { exit !found }' "$1" 2>/dev/null
}
proton_reg() {
  STEAM_COMPAT_DATA_PATH="$compat_dir" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
    "$proton" run reg "$@" >/dev/null 2>&1
  # Wine saves the registry files when its server exits.
  local server; server="$(dirname -- "$proton")/files/bin/wineserver"
  [[ -x $server ]] && WINEPREFIX="$prefix" "$server" -w
  return 0
}
# A Microsoft build, not Wine's builtin replacement.
microsoft_dll() { grep -aq 'Microsoft Corporation' "$1" 2>/dev/null && ! grep -aq 'Wine builtin DLL' "$1"; }
ini_args() { printf '%s\n' --bios "$bios_dir" --games "$games_dir"; }

dry_run() {
  say "PCSX2 2.8.1 for Windows from $archive into $pcsx2_dir (portable)"
  say "ReShade 6.8 dxgi.dll and nvngx_dlssnr.dll from ${pinnacle_host:-<Pinnacle of View host64 not found>}"
  say "DLSSNR Linux add-on and forwarder from $dlssnr_dir"
  say "d3dcompiler_47.dll from $downloads, ucrtbase.dll from $ucrtbase_src, icuuc.dll from $icu_src"
  say "iMMERSE Launchpad from $immerse_dir into reshade-shaders"
  say "Prefix $prefix: ${overrides[*]} = native,builtin"
  say "PCSX2.ini and ReShade.ini managed settings (configure_ini.py)"
  say "Launcher: $launcher_dst"
}

verify_inputs() {
  local entry name src want missing=0
  for entry in "${pinned[@]}"; do
    IFS='|' read -r name src want <<<"$entry"
    if [[ ! -f $src ]]; then warn "missing $name: $src (see README.md)"; missing=1
    elif [[ $(sha "$src") != "$want" ]]; then warn "$name does not match the tested build: $src"; missing=1
    fi
  done
  microsoft_dll "$ucrtbase_src" || { warn "no Microsoft ucrtbase.dll at $ucrtbase_src (set PCSX2_DLSS5_UCRTBASE)"; missing=1; }
  [[ -f $icu_src ]] || { warn "Proton's icu.dll not found: $icu_src (set PCSX2_DLSS5_PROTON)"; missing=1; }
  local f
  for f in "${immerse_files[@]}"; do
    [[ -f $immerse_dir/$f ]] || { warn "iMMERSE file missing: $immerse_dir/$f (see README.md)"; missing=1; }
  done
  return "$missing"
}

install_pcsx2() {
  mkdir -p -- "$pcsx2_dir" || return 1
  local want; want=$(bsdtar -xOf "$archive" pcsx2-qt.exe | sha256sum | cut -d' ' -f1)
  if [[ $(sha "$pcsx2_dir/pcsx2-qt.exe") != "$want" ]]; then
    bsdtar -xf "$archive" -C "$pcsx2_dir" || return 1
    say "PCSX2 2.8.1 extracted to $pcsx2_dir"
  fi
  : >>"$pcsx2_dir/portable.txt"
  local entry name src _
  for entry in "${pinned[@]:1}"; do
    IFS='|' read -r name src _ <<<"$entry"
    cmp -s "$src" "$pcsx2_dir/$name" || install -m644 -- "$src" "$pcsx2_dir/$name" || return 1
  done
  cmp -s "$ucrtbase_src" "$pcsx2_dir/ucrtbase.dll" || install -m644 -- "$ucrtbase_src" "$pcsx2_dir/ucrtbase.dll" || return 1
  # Qt6Core imports icuuc.dll, which Windows has and Wine does not; Wine's
  # icu.dll exports the same functions.
  cmp -s "$icu_src" "$pcsx2_dir/icuuc.dll" || install -m644 -- "$icu_src" "$pcsx2_dir/icuuc.dll" || return 1
  [[ -f $pcsx2_dir/depth-sizes.conf ]] || install -m644 -- "$component_dir/depth-sizes.conf" "$pcsx2_dir/depth-sizes.conf" || return 1
  say "PCSX2, ReShade, the add-on, the model and the runtime DLLs are in place"
}

install_shaders() {
  local dst="$pcsx2_dir/reshade-shaders"
  mkdir -p -- "$dst/Shaders" "$dst/Textures" || return 1
  cp -r -- "$immerse_dir/Shaders/." "$dst/Shaders/" && cp -r -- "$immerse_dir/Textures/." "$dst/Textures/" || return 1
  [[ -f $pcsx2_dir/ReShadePreset.ini ]] ||
    printf 'Techniques=MartysMods_Launchpad@MartysMods_LAUNCHPAD.fx\r\nTechniqueSorting=MartysMods_Launchpad@MartysMods_LAUNCHPAD.fx\r\n' \
      >"$pcsx2_dir/ReShadePreset.ini"
  say "iMMERSE Launchpad installed and enabled"
}

install_registry() {
  [[ -x $proton ]] || { warn "Proton not found: $proton (set PCSX2_DLSS5_PROTON)"; return 1; }
  mkdir -p -- "$compat_dir" || return 1
  local dll
  for dll in "${overrides[@]}"; do
    reg_has "$prefix/user.reg" "$overrides_key" "\"$dll\"=\"native,builtin\"" ||
      proton_reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native,builtin /f
  done
  for dll in "${overrides[@]}"; do
    reg_has "$prefix/user.reg" "$overrides_key" "\"$dll\"=\"native,builtin\"" || { warn "override $dll did not save"; return 1; }
  done
  say "Prefix overrides set: ${overrides[*]}"
}

install_settings() {
  local args; mapfile -t args < <(ini_args)
  python3 -I "$component_dir/configure_ini.py" pcsx2 "$pcsx2_dir/inis/PCSX2.ini" "${args[@]}" &&
    python3 -I "$component_dir/configure_ini.py" reshade "$pcsx2_dir/ReShade.ini"
}

install_launcher() {
  install -Dm755 -- "$component_dir/omarchy-pcsx2-dlss5" "$launcher_dst" && say "Launcher installed: $launcher_dst"
}

install_component() {
  if running; then warn "PCSX2 is running; close it and rerun"; return 1; fi
  verify_inputs || { warn "inputs are missing or differ; nothing was changed"; return 1; }
  local failed=() step
  for step in pcsx2 shaders registry settings launcher; do
    "install_$step" || failed+=("$step")
  done
  ((${#failed[@]} == 0)) || { warn "steps that need attention: ${failed[*]}"; return 1; }
}

uninstall_component() {
  if running; then warn "PCSX2 is running; close it and rerun"; return 1; fi
  rm -f -- "$launcher_dst"
  say "Removed $launcher_dst. $pcsx2_dir (settings, saves, states) and the prefix"
  say "$compat_dir are kept; delete them by hand to remove everything."
}

check_component() {
  local failures=0
  ok() { printf 'OK   pcsx2-dlss5: %s\n' "$*"; }
  fail() { printf 'FAIL pcsx2-dlss5: %s\n' "$*"; failures=$((failures + 1)); }

  local version
  version=$(strings -el "$pcsx2_dir/pcsx2-qt.exe" 2>/dev/null | grep -A1 -x FileVersion | tail -1)
  [[ $version == 2.8.1.* ]] && ok "PCSX2 $version in $pcsx2_dir" || fail "PCSX2 2.8.1 not found in $pcsx2_dir (found: ${version:-none})"
  [[ -f $pcsx2_dir/portable.txt ]] && ok "portable mode" || fail "portable.txt missing"
  local entry name _ want
  for entry in "${pinned[@]:1}"; do
    IFS='|' read -r name _ want <<<"$entry"
    [[ $(sha "$pcsx2_dir/$name") == "$want" ]] && ok "$name is the tested build" || fail "$name missing or different"
  done
  microsoft_dll "$pcsx2_dir/ucrtbase.dll" && ok "Microsoft ucrtbase.dll" || fail "ucrtbase.dll missing or Wine's"
  [[ -f $pcsx2_dir/icuuc.dll ]] && ok "icuuc.dll present" || fail "icuuc.dll missing: Qt does not start"
  [[ -f $pcsx2_dir/reshade-shaders/Shaders/MartysMods_LAUNCHPAD.fx && -f $pcsx2_dir/reshade-shaders/Textures/iMMERSE_bluenoise_opt.png ]] \
    && ok "iMMERSE Launchpad installed" || fail "iMMERSE Launchpad files missing"
  local dll
  for dll in "${overrides[@]}"; do
    reg_has "$prefix/user.reg" "$overrides_key" "\"$dll\"=\"native,builtin\"" && ok "prefix loads native $dll" \
      || fail "prefix lacks $dll=native,builtin"
  done
  local args; mapfile -t args < <(ini_args)
  python3 -I "$component_dir/configure_ini.py" --check pcsx2 "$pcsx2_dir/inis/PCSX2.ini" "${args[@]}" \
    && ok "PCSX2.ini managed settings" || fail "PCSX2.ini differs from the managed settings"
  python3 -I "$component_dir/configure_ini.py" --check reshade "$pcsx2_dir/ReShade.ini" \
    && ok "ReShade.ini managed settings" || fail "ReShade.ini differs from the managed settings"
  cmp -s "$component_dir/omarchy-pcsx2-dlss5" "$launcher_dst" && ok "launcher installed" || fail "launcher missing or outdated: $launcher_dst"
  [[ -x $proton ]] && ok "Proton: $proton" || fail "Proton not found: $proton"
  return "$failures"
}

case $action in
  install) install_component ;;
  uninstall) uninstall_component ;;
  dry-run) dry_run ;;
  check) check_component ;;
  *) printf 'ERROR pcsx2-dlss5: unknown action %s (install|check|dry-run|uninstall)\n' "$action" >&2; exit 2 ;;
esac
