# Need for Speed Most Wanted Remaster (PC) under Proton

The [DODI repack](https://dodi-repacks.site/964-need-for-speed-most-wanted-remastered-edition-dodi-repack/)
of GAMETEST's modded release, installed to
`~/Games/Need For Speed Most Wanted Remaster Edition`, run through the non-Steam
shortcut "Need for Speed: Most Wanted" (appid `3000485560`, UMU-Proton-10.0-4).

```bash
./components/nfsmw/nfsmw.sh install    # exit Steam and close the game first
./components/nfsmw/nfsmw.sh check      # non-mutating
./components/nfsmw/nfsmw.sh dry-run
```

Its artwork is in `userdata/<id>/config/grid/3000485560*` (cover, wide
capsule, hero and logo). They are SteamGridDB's top-rated assets for the 2005
game ([game 5258915](https://www.steamgriddb.com/game/5258915): grids 36920
and 29160, hero 20546, logo 2846), added by hand and not kept in this repo.

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
to the wheel, and playback, gain and autocentre are passed on. The wrapper
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

Pinnacle of View for Most Wanted (Nexus mod 328, in `~/Downloads/nfs-most-wanted/`)
is not installed. It is the same DXVK + ReShade-as-Vulkan-layer pack as the NFSU2
one, so it would need that component's patched DXVK and Khronos loader, and its
DLSS did not run under UMU-Proton 10 there.
