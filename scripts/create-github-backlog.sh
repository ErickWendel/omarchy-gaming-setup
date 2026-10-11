#!/usr/bin/env bash
set -euo pipefail

repo=${1:-ErickWendel/omarchy-gaming-setup}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

labels=(
  'foundation:5319e7' 'storage:d4c5f9' 'openrgb:2da44e' 'delta:0969da'
  'steam:1b2838' 'emulators:f97316' 'controllers:e11d48' 'testing:0e8a16'
  'wheel:8250df' 'priority:high:b60205' 'priority:medium:fbca04' 'blocked:000000'
)
for spec in "${labels[@]}"; do
  name=${spec%:*}
  color=${spec##*:}
  gh label create "$name" --repo "$repo" --color "$color" --force
done

create_issue() {
  local title=$1 file=$2 labels=$3
  if gh issue list --repo "$repo" --state all --search "in:title $title" --json title --jq '.[].title' | grep -Fxq "$title"; then
    echo "Issue already exists: $title"
    return
  fi
  gh issue create --repo "$repo" --title "$title" --body-file "$root/planning/issues/$file" --label "$labels"
}

create_issue 'Foundation: implement the idempotent Omarchy setup framework' '01-foundation.md' 'foundation,priority:high'
create_issue 'Storage: repair and reformat GExtended through verified local staging' '02-storage.md' 'storage,priority:high'
create_issue 'OpenRGB: reliably apply static-green after login' '03-openrgb.md' 'openrgb,priority:medium'
create_issue 'Delta: start the LCD controller hidden as a user service' '04-delta.md' 'delta,priority:medium'
create_issue 'Steam: fix Big Picture return and minimize lifecycle' '05-steam-big-picture.md' 'steam,priority:high'
create_issue 'Emulators: generate valid Omarchy and Steam application entries' '06-emulators.md' 'emulators,priority:high'
create_issue 'PCSX2: make both controllers work through Steam' '07-pcsx2.md' 'controllers,priority:high'
create_issue 'Integration: fresh-install and idempotency verification' '08-integration.md' 'testing,priority:high'
create_issue 'Logitech G29: support the wheel reliably in PS4 mode' '09-g29-wheel.md' 'wheel,controllers,priority:high'
