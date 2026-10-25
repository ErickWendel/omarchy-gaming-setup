#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wrapper="$repo_dir/components/assetto-corsa/ac-steam-wrapper"
test_root=$(mktemp -d)
trap 'kill "$(cat "$test_root/relay.pid" 2>/dev/null)" 2>/dev/null || true; rm -rf -- "$test_root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

proton_dir="$test_root/Proton 9.0 (Beta)"
mkdir -p "$proton_dir/files/bin"
printf '#!/bin/sh\n' >"$proton_dir/proton"
# Fake wineserver -k records the call and ends the lingering relay.
cat >"$proton_dir/files/bin/wineserver" <<EOF
#!/usr/bin/env bash
echo "\$WINEPREFIX \$*" >>"$test_root/wineserver.log"
[[ -f $test_root/relay.pid ]] && kill "\$(<"$test_root/relay.pid")" 2>/dev/null
exit 0
EOF
chmod +x "$proton_dir/proton" "$proton_dir/files/bin/wineserver"

# Fake launch: the game runs for a moment, the relay would run forever, and
# the launch (like Proton's waitforexitandrun) waits for both.
cat >"$test_root/launch" <<EOF
#!/usr/bin/env bash
bash -c 'exec -a "C:\\\\Steam\\\\assettocorsa\\\\AssettoCorsa.exe" sleep "\$1"' _ "\${GAME_SECONDS:-1}" &
bash -c 'exec -a "c:\\\\logi-tf-relay.exe" sleep 600' &
echo \$! >"$test_root/relay.pid"
wait
EOF
chmod +x "$test_root/launch"

export AC_POLL_SECONDS=0.2 AC_EXIT_POLLS=3 STEAM_COMPAT_DATA_PATH="$test_root/pfxroot"

# Game exits while the relay is still up: the wrapper kills the prefix.
start=$SECONDS
timeout 20 "$wrapper" "$test_root/launch" "$proton_dir/proton" waitforexitandrun game \
  || fail "wrapper did not return after the game exited"
((SECONDS - start < 10)) || fail "wrapper waited for the relay"
grep -Fxq "$test_root/pfxroot/pfx -k" "$test_root/wineserver.log" || fail "prefix not killed"
kill -0 "$(<"$test_root/relay.pid")" 2>/dev/null && fail "relay left running"

# While the game runs, the prefix is left alone.
rm -f "$test_root/wineserver.log"
GAME_SECONDS=3 timeout 20 "$wrapper" "$test_root/launch" "$proton_dir/proton" waitforexitandrun game &
wrapper_pid=$!
sleep 2
[[ ! -e $test_root/wineserver.log ]] || fail "prefix killed while the game was running"
wait "$wrapper_pid" || fail "wrapper failed with a longer game"
[[ -s $test_root/wineserver.log ]] || fail "prefix not killed after the longer game"

# A launch that exits on its own keeps its exit status.
printf '#!/bin/sh\nexit 7\n' >"$test_root/launch"
status=0
"$wrapper" "$test_root/launch" "$proton_dir/proton" >/dev/null || status=$?
((status == 7)) || fail "exit status not kept: $status"

echo "ac-steam-wrapper tests passed"
