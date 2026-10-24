#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fake_bin="$test_root/bin"
game="$test_root/F1 2020"
settings_dir="$test_root/steam/steamapps/compatdata/123/pfx/drive_c/users/steamuser/Documents/My Games/F1 2020/hardwaresettings"
settings="$settings_dir/hardware_settings_config.xml"
backups="$test_root/backups"
mkdir -p "$fake_bin" "$game/actionmaps" "$settings_dir"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/systemctl"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$fake_bin/pgrep"
chmod +x "$fake_bin/systemctl" "$fake_bin/pgrep"
export PATH="$fake_bin:$PATH"
export F1_2020_STEAM_ROOT="$test_root/steam" F1_2020_GAME_DIR="$game" F1_2020_BIN_DIR="$test_root/home/bin"
export F1_2020_UNIT_DIR="$test_root/home/units" F1_2020_BACKUP_DIR="$backups"

cat >"$game/actionmaps/logitech_g923.xml" <<'EOF'
        <Axis Name="di_z_axis_rotation+">
            <Action actionName="Accelerate">
                <Axis axisName="di_y_axis" type="uniDirectionalNegative" deadZone="0.0" saturation="1.0" />
            <Action actionName="Brake">
                <Axis axisName="di_z_axis_rotation" type="uniDirectionalNegative" deadZone="0.0" saturation="1.0" />
EOF
cat >"$settings" <<'EOF'
	<motion>
		<udp enabled="false" broadcast="false" ip="127.0.0.1" port="20777" sendRate="20" format="2020" yourTelemetry="restricted" />
	</motion>
EOF
original_map=$(cat "$game/actionmaps/logitech_g923.xml")

"$repo_dir/components/f1-2020/f1-2020.sh" install >/dev/null
grep -q 'axisName="di_z_axis" type' "$game/actionmaps/logitech_g923.xml"
! grep -q 'axisName="di_z_axis_rotation"' "$game/actionmaps/logitech_g923.xml"
# Tooltips name axes with Name=, which stays as it is.
grep -q 'Name="di_z_axis_rotation+"' "$game/actionmaps/logitech_g923.xml"
grep -q '<udp enabled="true" broadcast="false" ip="127.0.0.1" port="20778" sendRate="60" format="2020"' "$settings"
[[ $(cat "$backups/f1-2020/logitech_g923.xml") == "$original_map" ]]
grep -q 'enabled="false"' "$backups/f1-2020/hardware_settings_config.xml"
[[ -x $test_root/home/bin/omarchy-f1-2020-rev-lights && -f $test_root/home/units/omarchy-f1-2020-rev-lights.service ]]

# A second install changes nothing and keeps the original backups.
before=$(cat "$game/actionmaps/logitech_g923.xml" "$settings")
"$repo_dir/components/f1-2020/f1-2020.sh" install >/dev/null
[[ $(cat "$game/actionmaps/logitech_g923.xml" "$settings") == "$before" ]]
[[ $(cat "$backups/f1-2020/logitech_g923.xml") == "$original_map" ]]
"$repo_dir/components/f1-2020/f1-2020.sh" check >/dev/null

# With the game running, install refuses and edits nothing.
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/pgrep"
sed -i 's/axisName="di_z_axis" type/axisName="di_z_axis_rotation" type/' "$game/actionmaps/logitech_g923.xml"
if "$repo_dir/components/f1-2020/f1-2020.sh" install >/dev/null 2>&1; then
  echo 'install must refuse while the game runs' >&2; exit 1
fi
grep -q 'axisName="di_z_axis_rotation"' "$game/actionmaps/logitech_g923.xml"

echo 'F1 2020 component test passed'
