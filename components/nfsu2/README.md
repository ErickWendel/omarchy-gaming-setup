# Need for Speed Underground 2 (PC) + Pinnacle of View under Proton

The PC game from `~/Games/Need for Speed - Underground 2`, run through the
non-Steam shortcut `SPEED2.exe` (appid `2674037821`, UMU-Proton-10.0-4),
with the [Pinnacle of View](https://www.nexusmods.com/needforspeedunderground2/mods/111?tab=description)
mod: ReShade 6.8 with its add-on support, a DLSS add-on, a custom DXVK and
NFSU2 ASI plugins.

```bash
./components/nfsu2/nfsu2.sh install    # close the game first
./components/nfsu2/nfsu2.sh check      # non-mutating
./components/nfsu2/nfsu2.sh dry-run
./components/nfsu2/nfsu2.sh uninstall  # removes the d3d9/vulkan-1/layer chain only
```

`install` is idempotent and does not need Steam closed, since the shortcut is not
edited. It needs no launch options: NVAPI, which DLSS needs, is on by default in
UMU-Proton 10. The downloads are not committed; they are read from
`~/Downloads/nfsu2`:

| Input | Default | Override |
| --- | --- | --- |
| Pinnacle of View, extracted from the Nexus zip | `~/Downloads/nfsu2/PinancleofView*/` | `NFSU2_PINNACLE_DIR` |
| LunarG Vulkan Runtime components ([download](https://sdk.lunarg.com/sdk/download/latest/windows/vulkan-runtime-components.zip?u=)); 1.4.363 tested | `~/Downloads/nfsu2/vulkan-runtime-components.zip` | `NFSU2_VULKAN_RT_ZIP` |

The shortcut is named "Need for Speed: Underground 2" in Steam, with cover art in
`userdata/<id>/config/grid/2674037821*` (taken from the old PS2 shortcut). It replaced
the PCSX2 shortcut for the same game. Renaming a shortcut keeps its appid, so the
prefix and the window rules still match. The prefix comes from launching the shortcut once. The game folder's
`scripts/NFSU2ExtraOptions.asi` must stay: the game does not start without it.
Game files are overwritten without a backup. To undo, reinstall the game.

## Why it is set up this way

On Windows, Pinnacle's `d3d9.dll` is DXVK (D3D9 → Vulkan), and the ReShade
installer registers `reshade32.dll` as a **Vulkan implicit layer**. Pinnacle's
shaders (DLSS5_Feed, lumenite, BaBa GI, qUINT Lightroom) need ReShade's Vulkan
or D3D10+ backend. Under Proton three things break that chain:

1. Wine's builtin `vulkan-1.dll` does not load Windows layers. Fix: the real
   Khronos x86 `vulkan-1.dll` in the game folder, with
   `vulkan-1=native,builtin` in the prefix. It reads the layer registry and
   uses Wine's `winevulkan` as its driver.
2. DXVK loads `winevulkan.dll` directly when it detects Wine, which skips the
   loader. Fix: [`patch_dxvk.py`](patch_dxvk.py) renames both
   `winevulkan.dll` strings in Pinnacle's DXVK to `winevulkaX.dll`, so DXVK
   falls back to `vulkan-1.dll`.
3. The layer must be registered. Fix: [`ReShade32.json`](ReShade32.json) in the
   game folder, listed under
   `HKLM\Software\Wow6432Node\Khronos\Vulkan\ImplicitLayers`.

With this, `ReShade.log` shows "Requesting new Vulkan instance" and every effect
compiles.

DLSS itself does not run. The DLSS host (`host64/dlss5-feed-host.log`) reaches
`NVSDK_NGX_D3D12_Init -> Success` and creates a 3440x1440 DLAA feature, but no
game frame ever reaches it: the game side (`dlss5-feed.log`) fails to import
the host's shared textures, retrying every 5 to 30 seconds:

```
[feed32] texture import FAILED: slot 0 3440x1440 B8G8R8A8_UNORM (raw Vulkan external-memory import)
```

So DLSS is never evaluated (Deep Fried Chicken logs `neuralAttempts=0`), and
the host recreates the feature after each failed attempt. The neural rendering
model (NGX feature 18) is also unavailable through the driver: driver 610.57
answered `0xBAD0000C (OutOfDate)` and 615.78.08 answers `0xBAD00012
(NotImplemented)`. Both are solved under GE-Proton 11, at the cost of the
wheel; see [DLSS 5 with GE-Proton 11](#dlss-5-with-ge-proton-11-tested-rolled-back).

The DLSS add-on's 64-bit host opens its own screen-sized window, "DLSS 5 Feed
host", which is meant to stay hidden behind the game. Under Hyprland it took
fullscreen and focus, and the game was left tiled behind it. Pressing Home there
opens the host's own ReShade, which has no effects. [`components/hypr/gaming.lua`](../hypr/gaming.lua)
sends that window to a hidden special workspace and opens the game fullscreen.

Install also:

- disables `scripts/modupdater.asi`, which downloads and replaces plugins at
  launch;
- keeps PlayStation button prompts (`ImproveGamepadSupport = 2`) in the pack's
  WidescreenFix ini;
- points ReShade's `IntermediateCachePath` at `.\reshade-cache` instead of
  the author's `C:\Users\...` folder;
- copies Pinnacle's configs only on the first install, so later runs keep
  what you change in the ReShade menu.

## What did not work

- **DLSSNR Linux add-on under UMU-Proton 10** ([reshade-dlss5-linux](https://github.com/RianGoossens/reshade-dlss5-linux)
  v0.10.0, 2026-10-20). It ships only a 64-bit build, so it was tried in
  `host64/` with Deep Fried Chicken disabled. It loaded and hooked NGX, but saw
  no evaluate calls because of the texture import failure above. Under
  GE-Proton 11 it works (next section).
- **`WINEDLLOVERRIDES` in the environment or launch options.** Wine then
  ignores the prefix's registry overrides. `dinput8` (the ASI loader) stops
  loading, so ExtraOptions is off and the game crashes at `speed2+0x17985c` or
  fails to start. Put overrides in the prefix registry only.
- **ReShade as `d3d9.dll`, proxying to Pinnacle's DXVK.** It loads, but on
  its D3D9 backend, and the main shaders fail with "needs D3D10 or newer".
- **dgVoodoo2 (2.87.3 and 2.87.5) for D3D9 → D3D11.** It crashes inside its own
  `CreateDevice` for SPEED2 under Proton, with D3D11 or D3D12 output, one
  adapter, antialiasing off, and with or without plugins.
- **Texmod (`NFSU2Remake2024.tpf`).** Started from the file manager, it ran
  under system Wine (`~/.wine`), not the game's prefix. Under Proton, SPEED2
  hung at 100% CPU with ReShade also hooking d3d9. A 433 MB TPF is also too
  much for Texmod.

## DLSS 5 with GE-Proton 11 (tested, rolled back)

Tested on 2026-10-22 and rolled back the same day: DLSS 5 ran, but the
difference was not worth losing the wheel. To turn it on again:

1. With Steam closed, back up `steamapps/compatdata/2674037821`, then set the
   shortcut's compatibility tool to `GE-Proton11-1` in `config/config.vdf`
   (`CompatToolMapping`) and prefix its launch options in `shortcuts.vdf` with
   `PROTON_FORCE_NVAPI=1` (GE-Proton keeps NVAPI off). Keep the wheel wrapper.
   The first launch upgrades the prefix.
2. Copy `dlssnr-linux.addon64` and `nvngx.dll_nrfwd.dll` (DLSSNR Linux v0.10.0,
   the same files as [`components/pcsx2-dlss5`](../pcsx2-dlss5/README.md)) into
   `host64/`, next to Pinnacle's `nvngx_dlssnr.dll`, and disable Deep Fried
   Chicken there: `DisabledAddons=Deep Fried Chicken UniversalFrame Experimental 1.7.4@deep-fried-chicken.addon64`
   in `host64/ReShade.ini` (CRLF).

What happens then:

- Wine 11 imports the host's textures (`[feed32] ... semaphore import: in=OK
  out=OK`, `shared set ready`), so the host evaluates DLSS on every frame
  (`frame 5400 evaluated ... DLSS GPU 2.6 ms/frame`).
- Deep Fried Chicken alone still never tries feature 18 (`captured=401`,
  `neuralAttempts=0`), likely because the driver answers `NotImplemented`.
- DLSSNR in `host64/` picks up that DLSS session and bypasses the driver:
  `nr-fwd: source = the game's DLSS session`, `CreateFeature(18) ... Success`,
  then `EvaluateFeature ... Success` for every frame.
- Its settings are in the host's ReShade. In the game's ReShade (Home), DLSS 5
  Feed → "Show the DLSS 5 panel in-game" draws the host's overlay as a
  texture; close the game's overlay to click it. F10 does not reach the host,
  so compare with its "Enable Neural Rendering" checkbox. The panel's other
  mode fails: "the desktop compositor refused the thumbnail (0x80004001)".

What breaks: the wheel. Wine 11 gives the G29 and the handbrake bridge new
DirectInput instance GUIDs (now cached in the prefix registry, so stable) and
logs them in a new format, `instance product: 046d:c24f, instance: {GUID}`.
The wrapper reads both formats, and the Wheel Fix's `wheel_setup.exe` shows
every axis correctly. In the game, though, steering sat at full right lock and
the handbrake fired nitro even after resetting the game's Controls, so the
game itself reads the wheel differently under Wine 11. That is the open
problem if this is tried again.

To roll back: Steam closed, compatibility tool `UMU-Proton-10.0-4-proton`,
remove `PROTON_FORCE_NVAPI=1`, restore the backed-up prefix (only DXVK caches
change in it), remove the two DLSSNR files and re-enable Deep Fried Chicken.

## G29 wheel

Verified by the user on 2026-10-20: steering, pedals, paddles and the handbrake
work and the camera stays still. The handbrake bridge's `BTN_TRIGGER` arrives
as button 1, which the game reads as nitro; the wrapper turns it off (step 6).

### Why the game needs help

A released G29 pedal reports its axis maximum (255 released, 0 pressed). Wine
passes the pedals to DirectInput as `Z` (gas), `Rx` (brake) and `Y` (clutch).
NFSU2 binds axes as if the device were a gamepad and reads those maxed-out
axes as held. That spins the camera and makes rebinding grab the clutch.

### Setup

1. [NFSU2 Wheel Fix](https://www.nexusmods.com/needforspeedunderground2/mods/115)
   1.0: `scripts/ffb.asi`, `ffb.ini` and `wheel_setup.exe` in the game folder.
   The Widescreen Fix's `dinput8.dll` loads it.
2. Run `wheel_setup.exe` with `WINEDLLOVERRIDES="dinput8=b"`. Without the
   override the game folder's ASI loader injects the game's mods into the tool.
3. Steam launch option for the shortcut:

   ```
   /home/<user>/.local/bin/nfsu2-wheel-wrapper %command%
   ```

   With a G29 connected, `nfsu2-wheel-wrapper` sets new-lg4ff
   `combine_pedals=1` for the session. Gas and brake then share a centred `Z`
   axis, and `Rx` stays centred. It also sets WidescreenFix
   `ImproveGamepadSupport = 0` (otherwise the fix treats the wheel as an Xbox
   pad and fires menu actions from the pedals) and turns the split-screen
   plugin off. Without the G29 it turns `ffb.asi` off instead (see
   [Split screen](#split-screen)). Both plugins hook DirectInput.
   Everything is restored on exit, so other games keep separate pedals and
   `nfsu2.sh check` still sees `ImproveGamepadSupport = 2`. Plugins it turned
   off are renamed `*.asi.wrapper-off`, and a killed session's leftovers are
   renamed back at the next launch.
   `ffb.ini` names devices by DirectInput instance GUID. Wine builds that GUID
   from a handle it hands out as devices appear, so it changes whenever the set
   of connected controllers changes. Connecting two DualSenses moved the
   handbrake from `…EDE` to `…ED2`, and the lever went dead. In wheel mode the
   wrapper first lists the prefix's devices with Wine's joystick panel in a
   headless gamescope (about 3 s) and rewrites the G29 and handbrake GUIDs.
   The mod doesn't accept product GUIDs. Each launch is logged to
   `~/.local/state/nfsu2-wheel-wrapper.log`.
   Install it with `install -m755 nfsu2-wheel-wrapper ~/.local/bin/`.
4. Pedal lines in `ffb.ini` (`{device}|axis|released|pressed`). Set them by
   hand: Wine reports an axis as centred until the wheel sends a report, so
   Detect records mid-axis "released" values.

   ```
   throttle  = {G29}|Z|32639|983
   brake     = {G29}|Z|32639|54000   ; full brake at about 2/3 of the travel
   handbrake = {handbrake}|X|1966|63569
   ```

5. In the game's Controls, clear any axis binding for gas and brake left over
   from before the mod. A stale gas binding on `Y`, the idle clutch, holds the
   throttle open.
6. The prefix must not disable the G29 or the handbrake under
   `HKCU\Software\Wine\DirectInput\Joysticks`. The game also polls the
   handbrake bridge as a joystick of its own, which its Controls screen does
   not offer, and fires nitro on that device's button 1 whatever the wheel's
   Nitro binding is. A `+dinput` trace (2026-10-22) shows the game opening both
   devices and reading them with plain `GetDeviceState`; with the mod's
   handbrake unmapped, the lever still fired nitro. So in wheel mode the
   wrapper creates `/run/omarchy-handbrake/axis-only`, and the bridge then
   sends only the lever's axis (which the Wheel Fix reads) and no button.

## G923 Xbox edition

Verified by the user on 2026-10-23: gas, brake and steering work, the camera
stays still and the menus no longer scroll by themselves. The wrapper treats a
G923 in PC mode (`046d:c26e`, see [`components/g923`](../g923/README.md)) like
the G29: wheel mode, Wheel Fix GUIDs rewritten for `046d:c26e`, split-screen
off, `ImproveGamepadSupport = 0` and the handbrake axis-only flag. The G29 wins
when both are connected.

Differences from the G29:

- **No `combine_pedals`; the Wheel Fix combines instead.** The G923 runs on
  `logitech-trueforce-dkms` (`hid-logitech-dd`), not new-lg4ff; it was set up
  on `hid-logitech-hidpp`, which has no pedal combining at all. The driver's
  `wheel_combined_pedals` is not used, and `g923_pedal_invert=N` keeps the
  pedals as below. Its released pedals sit at the axis
  maximum (`ABS_Y`, `ABS_Z`, `ABS_RZ` = 255 on evdev). The game's own
  bindings, made with the G29, read the raw `Z` axis, which on the G29 was the
  combined pedal axis (centred, gas low, brake high) but on the G923 is the
  brake alone: pressing the brake accelerated, and `pedals_to = S0` or `-S0`
  made no difference. `pedals_to = -Z` has the Wheel Fix write its combined
  pedals over `Z`, so the game sees the G29's layout. The Wheel Fix accepts
  an optional `-` and one of its 8 axis names as a target (`ParseTarget`).
- **Clutch.** The clutch is `Rx`, resting at its maximum; pressing it scrolls
  menus. The game does not use it (`clutch = off`), so leave it alone in
  menus.
- **Per-wheel lines.** `ffb.ini` has one set of pedal and button lines, so
  each wheel keeps its own `throttle`, `brake`, `clutch`, `nitrous`, `seq_up`,
  `seq_down` and `pedals_to` lines (in `ffb.ini` format) in `ffb-wheel.g29.ini` /
  `ffb-wheel.g923.ini` next to it, and the wrapper copies the connected
  wheel's set in. A wheel without a profile keeps whatever `ffb.ini` has; the
  previous wheel's lines are saved as its profile first if it has none. The
  last wheel used is in `~/.local/state/nfsu2-wheel-wrapper.wheel`.

G923 mapping from `wheel_setup.exe` (2026-10-23): gas `Y`, brake `Z`, clutch
`Rx`, released near 64000 and pressed near 2000 (brake 17921, part travel);
nitrous is button 2. The paddles were left at the G29's 5/6. `pedals_to = -Z`.

To retune a wheel: map it in `wheel_setup.exe` (step 2; press each pedal,
Detect records centred values otherwise) with only that wheel connected, then
copy the changed lines into its `ffb-wheel.<wheel>.ini`.

## Split screen

[NFSU2-SplitScreen](https://github.com/mihaits/NFSU2-SplitScreen) 0.9.4 alpha
(`NFSU2SplitScreen.asi` and `.ini` in `scripts/`) adds a native 2-4 player
"Split-Screen" entry next to Quick Race. Players join by pressing START on
their own XInput pad. Proton's SDL backend presents each DualSense as one,
so DS4Windows isn't needed. The plugin hides real DirectInput controllers,
so it can't use the wheel. The wrapper only enables it with the G29
unplugged. Verified 2026-10-20 with two DualSenses.
