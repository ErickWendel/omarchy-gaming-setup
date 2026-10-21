#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/pcsx2-dlss5/pcsx2-dlss5.sh"
launcher="$repo_dir/components/pcsx2-dlss5/omarchy-pcsx2-dlss5"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$test_root/home"
export PCSX2_DLSS5_STEAM_ROOT="$test_root/steam"
export PCSX2_DLSS5_DIR="$test_root/games/PCSX2-Windows"
export PCSX2_DLSS5_PREFIX="$test_root/prefix"
export PCSX2_DLSS5_PROTON="$test_root/proton/proton"
export PCSX2_DLSS5_DOWNLOADS="$test_root/downloads"
export PCSX2_DLSS5_DLSSNR_DIR="$test_root/dlssnr"
export PCSX2_DLSS5_PINNACLE_HOST="$test_root/pinnacle/host64"
export PCSX2_DLSS5_UCRTBASE="$test_root/ucrtbase.dll"
export PCSX2_DLSS5_PROCESS=omarchy-test-no-such-process
mkdir -p "$HOME" "$PCSX2_DLSS5_DOWNLOADS" "$PCSX2_DLSS5_DLSSNR_DIR" "$PCSX2_DLSS5_PINNACLE_HOST" "$(dirname "$PCSX2_DLSS5_PROTON")"

"$script" dry-run | grep -q 'Launcher: .*omarchy-pcsx2-dlss5' || fail "dry-run does not name the launcher"

# Missing inputs: install refuses and changes nothing.
if "$script" install 2>"$test_root/err"; then fail "install succeeded without inputs"; fi
grep -q 'missing pcsx2-v2.8.1-windows-x64-Qt.7z' "$test_root/err" || fail "missing archive not reported"
grep -q 'no Microsoft ucrtbase.dll' "$test_root/err" || fail "missing ucrtbase not reported"
[[ ! -e $PCSX2_DLSS5_DIR && ! -e $HOME/.local/bin/omarchy-pcsx2-dlss5 ]] || fail "install changed files despite missing inputs"

# An input that is not the tested build is rejected by checksum.
echo 'not the add-on' >"$PCSX2_DLSS5_DLSSNR_DIR/dlssnr-linux.addon64"
"$script" install 2>"$test_root/err" && fail "install accepted a changed add-on"
grep -q 'dlssnr-linux.addon64 does not match the tested build' "$test_root/err" || fail "checksum mismatch not reported"

# Wine's builtin ucrtbase is not accepted.
printf 'Microsoft Corporation\0Wine builtin DLL' >"$PCSX2_DLSS5_UCRTBASE"
"$script" install 2>"$test_root/err" && fail "install accepted Wine's ucrtbase"
grep -q 'no Microsoft ucrtbase.dll' "$test_root/err" || fail "Wine ucrtbase not rejected"

# check reports a missing installation as failures, not a crash.
if "$script" check >"$test_root/out"; then fail "check passed on an empty install"; fi
grep -q 'FAIL pcsx2-dlss5: PCSX2 2.8.1 not found' "$test_root/out" || fail "check missing PCSX2 not reported"

# Launcher: Windows path for the ROM, -batch, NVAPI forced, depth size from
# the internal resolution and depth-sizes.conf. No hyprctl on PATH, so no
# window watcher.
mkdir -p "$PCSX2_DLSS5_DIR/inis" "$test_root/bin"
touch "$PCSX2_DLSS5_DIR/pcsx2-qt.exe"
printf '[EmuCore/GS]\r\nupscale_multiplier = 3\r\n' >"$PCSX2_DLSS5_DIR/inis/PCSX2.ini"
cat >"$PCSX2_DLSS5_PROTON" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PCSX2_DLSS5_DIR/proton-args"
printf 'NVAPI=%s\n' "$PROTON_FORCE_NVAPI" >>"$PCSX2_DLSS5_DIR/proton-args"
EOF
chmod +x "$PCSX2_DLSS5_PROTON"
for tool in bash sed tr head paste pgrep python3 mkdir; do ln -s "$(command -v "$tool")" "$test_root/bin/$tool"; done
PATH="$test_root/bin" PCSX2_DLSS5_GPU="RTX test" "$launcher" "'/run/media/u/G/roms/ps2/Burnout 3 (USA).iso'" ||
  fail "launcher failed"
args=$(cat "$PCSX2_DLSS5_DIR/proton-args")
grep -qx 'run' <<<"$args" || fail "proton not called with run"
grep -qx -- '-batch' <<<"$args" || fail "launcher does not pass -batch"
grep -qxF 'Z:\run\media\u\G\roms\ps2\Burnout 3 (USA).iso' <<<"$args" || fail "ROM path not converted: $args"
grep -qx 'NVAPI=1' <<<"$args" || fail "NVAPI not forced"

echo "pcsx2-dlss5 tests passed"
