# Need for Speed Underground 2 (PC) with the G29

Non-Steam shortcut `SPEED2.exe` under UMU-Proton 10. Verified by the user on
2026-10-20: steering, pedals and paddles work and the camera stays still.
Known issue: the handbrake bridge's `BTN_TRIGGER` arrives as button 1, which
the game's default bindings use for nitro (see step 6).

## Why the game needs help

A released G29 pedal reports its axis maximum (255 released, 0 pressed). Wine
passes the pedals to DirectInput as `Z` (gas), `Rx` (brake) and `Y` (clutch).
NFSU2 binds axes as if the device were a gamepad and reads those maxed-out
axes as held. That spins the camera and makes rebinding grab the clutch.

## Setup

1. [NFSU2 Wheel Fix](https://www.nexusmods.com/needforspeedunderground2/mods/115)
   1.0: `scripts/ffb.asi`, `ffb.ini` and `wheel_setup.exe` in the game folder.
   The Widescreen Fix's `dinput8.dll` loads it.
2. Run `wheel_setup.exe` with `WINEDLLOVERRIDES="dinput8=b"`. Without the
   override the game folder's ASI loader injects the game's mods into the tool.
3. Steam launch option for the shortcut:

   ```
   /home/<user>/.local/bin/nfsu2-wheel-wrapper %command%
   ```

   `nfsu2-wheel-wrapper` sets new-lg4ff `combine_pedals=1` while the game runs
   and restores the previous value on exit. Gas and brake then share a centred
   `Z` axis, and `Rx` stays centred. Other games keep separate pedals.
   It also sets WidescreenFix `ImproveGamepadSupport` on each launch: `0` with
   the G29 connected (otherwise the fix treats the wheel as an Xbox pad and
   fires menu actions from the pedals), `2` (PlayStation labels) without it.
   Install it with `install -m755 nfsu2-wheel-wrapper ~/.local/bin/`.
4. Pedal lines in `ffb.ini` (`{device}|axis|released|pressed`). Set them by
   hand: Wine reports an axis as centred until the wheel sends a report, so
   Detect records mid-axis "released" values.

   ```
   throttle = {G29}|Z|32639|983
   brake    = {G29}|Z|32639|54000   ; full brake at about 2/3 of the travel
   ```

5. In the game's Controls, clear any axis binding for gas and brake left over
   from before the mod. A stale gas binding on `Y`, the idle clutch, holds the
   throttle open.
6. The prefix must not disable the G29 or the handbrake under
   `HKCU\Software\Wine\DirectInput\Joysticks`. Move the game's own Nitro
   binding off button 1, or the handbrake lever fires nitro.
