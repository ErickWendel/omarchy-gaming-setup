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
compiles. The DLSS host (`host64/dlss5-feed-host.log`) shows
`NVSDK_NGX_D3D12_Init -> Success` and DLAA at 3440x1440. The optional
"neural rendering" model reports OutOfDate and stays off.

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

## G29 wheel

Verified by the user on
2026-10-20: steering, pedals and paddles work and the camera stays still.
Known issue: the handbrake bridge's `BTN_TRIGGER` arrives as button 1, which
the game's default bindings use for nitro (see step 6).

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

## Split screen

[NFSU2-SplitScreen](https://github.com/mihaits/NFSU2-SplitScreen) 0.9.4 alpha
(`NFSU2SplitScreen.asi` and `.ini` in `scripts/`) adds a native 2-4 player
"Split-Screen" entry next to Quick Race. Players join by pressing START on
their own XInput pad. Proton's SDL backend presents each DualSense as one,
so DS4Windows isn't needed. The plugin hides real DirectInput controllers,
so it can't use the wheel. The wrapper only enables it with the G29
unplugged. Verified 2026-10-20 with two DualSenses.
