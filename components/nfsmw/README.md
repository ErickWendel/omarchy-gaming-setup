# Need for Speed Most Wanted Remaster (PC) under Proton

The [DODI repack](https://dodi-repacks.site/964-need-for-speed-most-wanted-remastered-edition-dodi-repack/)
of GAMETEST's modded release, installed to
`$GEXTENDED_MOUNT/Games/Need For Speed Most Wanted Remaster Edition`, run through the non-Steam
shortcut "Need for Speed: Most Wanted" (appid `3000485560`, UMU-Proton-10.0-4).

```bash
./components/nfsmw/nfsmw.sh install    # exit Steam and close the game first
./components/nfsmw/nfsmw.sh check      # non-mutating
./components/nfsmw/nfsmw.sh dry-run
```

Its artwork is in `userdata/<id>/config/grid/3000485560*` (cover, wide
capsule, hero, logo and icon). They are SteamGridDB's top-rated assets for the 2005
game ([game 5258915](https://www.steamgriddb.com/game/5258915): grids 36920
and 29160, hero 20546, logo 2846, icon 9098), added by hand and not kept in this repo.
The icon only shows once the shortcut's `icon` field in `shortcuts.vdf` points at
`grid/3000485560_icon.png`; write that with Steam closed.

`install` is idempotent:

- adds the shortcut to `shortcuts.vdf` and maps it to UMU-Proton-10.0-4 in
  `config.vdf` (both backed up under `~/.local/state/omarchy-gaming-setup/backups/`).
  The appid is the one Steam computes for the shortcut itself, so the prefix,
  `steamapps/compatdata/3000485560`, matches it;
- copies Microsoft's 32-bit `d3dcompiler_47.dll` into the game folder, from
  the winetricks cache (`~/.cache/winetricks/d3dcompiler_47/d3dcompiler_47_32.dll`;
  run `winetricks --force d3dcompiler_47` in any prefix to fetch it, or set
  `NFSMW_D3DCOMPILER`);
- points ReShade's `IntermediateCachePath` in `d3d9.ini` at `.\reshade-cache`
  instead of the repacker's `C:\Users\...` folder;
- sets `dinput8` (ASI loader), `d3d9` (ReShade) and `d3dcompiler_47` to
  `native,builtin` in the prefix registry. Do not put them in
  `WINEDLLOVERRIDES`: Wine then ignores the prefix's overrides.

- sets `DisableHidraw` for Wine's HID bus in the prefix (see
  [G923 wheel](#g923-wheel-xbox-edition));
- installs `nfsmw-wheel-wrapper` and `nfsmw-wheel-bridge` to `~/.local/bin`
  (`NFSMW_BIN_DIR`) and sets the shortcut's launch option to
  `~/.local/bin/nfsmw-wheel-wrapper %command%`. Launch options you set
  yourself are kept, and `check` reports them.

## G923 wheel (Xbox edition)

Verified by the user on 2026-10-24: steering, gas, brake, paddles and force
feedback work in races, the menus stay still, and the DualSense keeps its
prompts. This uses the G923 on `hid-logitech-dd` with `g923_pedal_invert=N`
(see [`components/g923`](../g923/README.md)). No Most Wanted counterpart of
the NFSU2 Wheel Fix turned up, and xan1242's
[XtendedInput](https://github.com/xan1242/NFS-XtendedInput) supports only
XInput pads, so the fix lives outside the game.

The game failed in two ways:

1. **No controller at all.** The TrueForce package gives the session the
   wheel's `hidraw` nodes, so Wine opened the wheel through hidraw. Both of
   its HID interfaces have vendor-page top collections (`fffd:fd01`,
   `ff72:00a1`), which DirectInput skips (`device usage ... not
   implemented` in a `+dinput` trace). With `DisableHidraw=1` under
   `HKLM\System\CurrentControlSet\Services\winebus` (the NFSU2 prefix had it
   already), Wine reads the wheel through SDL and the game finds it.
   Steering and force feedback then worked.
2. **Pedals read as held.** Most Wanted treats every axis as centred at rest.
   The G923's released pedals rest at the end of their range (`Y` gas, `Z`
   brake, `Rz` clutch at 255), so the menus scrolled by themselves and the
   Controls menu bound `Z` to whatever was pressed. The driver can switch
   the wheel's firmware to combined pedals (`wheel_combined_pedals`), but that
   moves only the gas and brake onto `Y`: `Z` and `Rz` still sit at 255.
   Turning WidescreenFix `ImproveGamepadSupport` off, as NFSU2 needs, did
   not help either, and it swaps the DualSense's buttons (X backs out).

`nfsmw-wheel-wrapper` starts `nfsmw-wheel-bridge` for the session. The bridge
mirrors the wheel to a uinput device, "Omarchy NFS Wheel" (`1209:4843`), with
only steering on `X`, gas and brake combined on a centred `Y` (gas low, brake
high), the buttons and the D-pad. Force feedback uploaded to it is uploaded
to the wheel, and playback, gain and autocentre are passed on. The bridge
keeps that state: when the wheel resets and re-enumerates mid-game it
re-uploads the effects, restores gain and autocentre and restarts the effects
that were playing. The wrapper
appends `0x046d/0xc26e` to `SDL_GAMECONTROLLER_IGNORE_DEVICES`, which both
Wine's SDL and evdev backends honour, so the game sees only the virtual
wheel. The bridge stops when the game exits, and the wheel itself is not
reconfigured, so other games are not affected. Without a G923, or if the
bridge does not come up within 3 s, the game is started as it is. Each
launch is logged to `~/.local/state/nfsmw-wheel-wrapper.log`.

The bridge reads the driver's `g923_pedal_invert` parameter, so it also works
with the driver default (released pedals at 0).

Bind the controls in Options → Controls: gas and brake are both on `Y`.
The downshift paddle starts out bound to the camera; rebind Shift Up/Down
to the paddles.

Not tried: the G29. It would need its own entry in the bridge's `SOURCE_IDS`
and in the wrapper.

## What the repack contains

All the script mods from the repack's list are in `scripts/`: Extra Options,
Widescreen Fix, Unlimiter, HUD Adapter, HD Reflections, Xbox rain droplets,
HD Fonts and Xbox 360 Stuff, plus MWFixes. The 77 added cars are in `CARS/`.
The remaining mods (Cut Races, HD vinyls/logos/UI, cameras, exhaust flames,
cop models and explosions, Smol Fix) are patched into `GLOBAL/`, `FRONTEND/`
and `TRACKS/`. The five texture packs in `Texture Mods/` only work through
`Texmod.exe`, which did not work under Proton for NFSU2 (see
[`components/nfsu2`](../nfsu2/README.md#what-did-not-work)).

## ReShade shader errors

The repack's ReShade (`d3d9.dll`, preset `GAMETEST_NFSMW_RESHADE.ini`) compiles
effects with `d3dcompiler_47`. Wine's builtin compiler failed on Vignette,
FilmicPass, qUINT SSR, qUINT MXAO, AmbientLight, MXAO, Levels, MagicBloom, SMAA,
FXAA and Vibrance (`E5002: Static variables cannot have both numeric and
resource components` in `d3d9.log`). With Microsoft's DLL every effect compiles.

## Pinnacle of View

Pinnacle of View for Most Wanted (Nexus mod 328) is the same pack as the
[NFSU2 one](../nfsu2/README.md#why-it-is-set-up-this-way): ReShade 6.8 as a
Vulkan layer on a custom DXVK `d3d9.dll`, with lumenite, BaBa GI and qUINT
Lightroom, plus newer WidescreenFix and HD Reflections builds. Extract the
zip into `~/Downloads/nfs-most-wanted/` (`NFSMW_PINNACLE_DIR`), then, with the
game closed:

```bash
./components/nfsmw/nfsmw.sh pinnacle          # switch to Pinnacle of View
./components/nfsmw/nfsmw.sh pinnacle-revert   # back to the repack's ReShade
```

`pinnacle` first copies the repack's `d3d9.dll`, `d3d9.ini`, `scripts/` and
`reshade-shaders/` to `~/.local/state/omarchy-gaming-setup/backups/nfsmw-pre-pinnacle`
(once, so it always holds the repack's files). It then uses the NFSU2
component's [`patch_dxvk.py`](../nfsu2/patch_dxvk.py) and
[`ReShade32.json`](../nfsu2/ReShade32.json), the Khronos x86 `vulkan-1.dll`
from `~/Downloads/nfsu2/vulkan-runtime-components.zip` (`NFSMW_VULKAN_RT_ZIP`),
and registers the layer and `vulkan-1=native,builtin` in the prefix. The
repack's ASI loader and its other mods (MWFixes, MW360Tweaks, Unlimiter,
Extra Options) stay. On the first switch:

- Pinnacle's WidescreenFix ini keeps the repack's Xbox prompts
  (`ImproveGamepadSupport = 1`) and `WriteSettingsToFile = 1`, so the game
  keeps reading its settings from `settings.ini`;
- the repack's Extra Options settings stay, including its visual treatment
  override (`EnableVisualTreatmentOverride = 1`). Without it the game's own
  yellow-green filter and bloom come back and, on top of Pinnacle's bloom,
  wash the picture out;
- Pinnacle's configs are copied only then, so later runs keep ReShade menu
  changes. `pinnacle-revert` drops them.

Tested 2026-10-24 on UMU-Proton-10.0-4: "Requesting new Vulkan instance" in
`ReShade.log`, every effect compiles, the game opens fullscreen, and
[`components/hypr/gaming.lua`](../hypr/gaming.lua) parks the DLSS host window
on `special:nfsmw-dlss-host`. As in NFSU2, DLSS itself does not run there
(`[feed32] texture import FAILED` in `dlss5-feed.log`); it would need GE-Proton
11, which the NFSU2 test showed changes how the game reads the wheel.

On the first switch `pinnacle` also replaces the preset's
`Lumenite_AnamorphicBloom` section with [`pinnacle-bloom.ini`](pinnacle-bloom.ini),
the one tuned in NFSU2. The pack's own streaks (Streak Stretch 10, Intensity
0.54) smeared glow across the screen and washed the picture out; the NFSU2
values (Stretch 0.63, Intensity 0.08, Bloom Intensity 0.4, sky excluded)
fixed it (user-verified 2026-10-24). Further tuning is in the ReShade menu
(Home); the preset saves itself.
