#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/components/forza-horizon-5/forza-horizon-5.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export FH5_STEAM_ROOT="$test_root/steam"
export FH5_BIN_DIR="$test_root/home/.local/bin"
export FH5_BACKUP_DIR="$test_root/backups"
export FH5_STEAM_PROCESS=omarchy-test-no-such-process
wrapper="$FH5_BIN_DIR/omarchy-forza-rev-lights"
config="$FH5_STEAM_ROOT/userdata/1/config/localconfig.vdf"
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$(dirname "$config")"
cat >"$config" <<'EOF'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"1551360"
					{
						"LaunchOptions"		"PROTON_ENABLE_HIDRAW=0x046D/0xC219 /home/u/.local/bin/omarchy-match-resolution %command%"
					}
					"244210"
					{
						"LaunchOptions"		"other %command%"
					}
				}
			}
		}
	}
}
EOF

output=$("$script" check) && fail "check passed before installation"
grep -q 'wrapper missing' <<<"$output" || fail "missing wrapper not reported"

"$script" dry-run >/dev/null
[[ ! -e $wrapper ]] || fail "dry-run installed files"

FH5_STEAM_PROCESS=bash "$script" install >/dev/null 2>&1 && fail "install passed while Steam was running"
grep -q 'omarchy-forza-rev-lights' "$config" && fail "launch options changed with Steam running"

"$script" install >/dev/null || fail "install failed"
cmp -s "$repo_dir/components/forza-horizon-5/forza-rev-lights" "$wrapper" || fail "wrapper not installed"
grep -Fq "\"PROTON_ENABLE_HIDRAW=0x046D/0xC219 /home/u/.local/bin/omarchy-match-resolution $wrapper %command%\"" "$config" \
  || fail "launch options not set: $(grep LaunchOptions "$config")"
grep -Fq '"other %command%"' "$config" || fail "another game's launch options changed"
ls "$FH5_BACKUP_DIR"/*/localconfig.vdf >/dev/null || fail "Steam config not backed up"

output=$("$script" check) || true
grep -q 'OK   forza-horizon-5: Steam launch options use the wrapper' <<<"$output" || fail "check: $output"
grep -q 'OK   forza-horizon-5: rev-light wrapper installed' <<<"$output" || fail "check: $output"

"$script" install >/dev/null || fail "rerun failed"
[[ $(grep -o 'omarchy-forza-rev-lights' "$config" | wc -l) == 1 ]] || fail "rerun added the wrapper twice"

"$script" uninstall >/dev/null || fail "uninstall failed"
[[ ! -e $wrapper ]] || fail "wrapper not removed"
grep -Fq '"PROTON_ENABLE_HIDRAW=0x046D/0xC219 /home/u/.local/bin/omarchy-match-resolution %command%"' "$config" \
  || fail "uninstall did not restore the launch options: $(grep LaunchOptions "$config")"

echo "forza-horizon-5 tests passed"
