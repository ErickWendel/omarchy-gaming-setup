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

The prefix comes from launching the shortcut once. The repack's own
`scripts/NFSU2ExtraOptions.asi` must stay: it skips the "Please insert Disc 2"
check. Game files are overwritten without a backup. To undo, reinstall the game.

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
  asks for Disc 2. Put overrides in the prefix registry only.
- **ReShade as `d3d9.dll`, proxying to Pinnacle's DXVK.** It loads, but on
  its D3D9 backend, and the main shaders fail with "needs D3D10 or newer".
- **dgVoodoo2 (2.87.3 and 2.87.5) for D3D9 → D3D11.** It crashes inside its own
  `CreateDevice` for SPEED2 under Proton, with D3D11 or D3D12 output, one
  adapter, antialiasing off, and with or without plugins.
- **Texmod (`NFSU2Remake2024.tpf`).** Started from the file manager, it ran
  under system Wine (`~/.wine`), not the game's prefix. Under Proton, SPEED2
  hung at 100% CPU with ReShade also hooking d3d9. A 433 MB TPF is also too
  much for Texmod.
