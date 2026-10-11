# Steam: fix Big Picture return and minimize lifecycle

## Problem

The PS5 Steam Big Picture monitor currently sets `restore_big_picture` to true after a qualifying launch and never resets it. After a game closes, this can make Steam leave Big Picture unexpectedly and then reopen Big Picture when the user intentionally minimizes or closes it.

The existing PS5 helper repository also has one local commit on `main` that has not been pushed. Preserve that work: inspect and build on it rather than resetting, overwriting, or force-pushing it.

## Goal

Model the helper lifecycle explicitly so a game started from Big Picture returns to Big Picture exactly once after the game exits, while manual minimize or close actions remain respected.

## Implementation notes

- Replace the persistent restore flag with explicit lifecycle states, at minimum: idle, Big Picture active, game active with return armed, and return completed/disarmed.
- Arm restoration only after detecting that a game was launched from Big Picture.
- On game/overlay exit, request Big Picture restoration once and immediately disarm the request, including when Steam is slow to recreate its window.
- Treat a later manual minimize or close as user intent; it must not re-arm or reopen Big Picture.
- Preserve existing PS-button behavior and avoid competing with Steam's own in-game overlay transitions.
- Handle missing, delayed, or rapidly changing Steam windows without entering a restore loop.
- Keep changes in the PS5 helper repository; pin the resulting published commit or release from this umbrella setup repository.

## Tests

Add deterministic state-machine tests with mocked process/window observations for:

- Big Picture -> game -> game exit -> exactly one Big Picture restore -> idle/disarmed.
- Manual Big Picture minimize after a completed return does not reopen it.
- Manual Big Picture close without a running game does not reopen it.
- Repeated PS-button presses do not create duplicate restore requests.
- Steam window temporarily missing during game/overlay transitions does not cause a loop.
- Overlay closes before the game process, and game closes before the overlay, with restoration occurring only after the session has ended.
- A game not launched from Big Picture never arms restoration.

## Dependencies

- Coordinate with the foundation issue for how the umbrella installer pins and installs the helper.
- This issue can otherwise be implemented in parallel with storage, OpenRGB, and Delta work.
- The final integration issue depends on this issue.

## Acceptance criteria

- Closing a game launched from Big Picture restores Big Picture exactly once.
- Minimizing or closing Big Picture afterward leaves it minimized or closed.
- No polling cycle or repeated PS-button input can trigger an endless reopen loop.
- Existing supported PS-button and overlay behavior continues to work.
- Automated state-machine tests cover the lifecycle and timing cases above.
- The pre-existing local commit on the helper's `main` branch is retained in history and no user work is discarded.
- The umbrella repository references a published, immutable helper commit or release containing the fix.
