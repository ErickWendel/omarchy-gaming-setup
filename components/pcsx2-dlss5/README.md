# PCSX2 with DLSS 5 (Windows build under Proton)

PS2 games with NVIDIA's DLSS 5 neural rendering (NGX feature 18), through
[DLSSNR Linux](https://github.com/RianGoossens/reshade-dlss5-linux), a ReShade
add-on. Feature 18 only exists for Windows programs, so this runs the Windows
build of PCSX2 2.8.1 in its own Proton prefix (GE-Proton11-1). It sits next to
the native Linux PCSX2 of [`components/pcsx2`](../pcsx2).

```bash
./components/pcsx2-dlss5/pcsx2-dlss5.sh install    # close PCSX2 first
./components/pcsx2-dlss5/pcsx2-dlss5.sh check      # non-mutating
./components/pcsx2-dlss5/pcsx2-dlss5.sh dry-run
./components/pcsx2-dlss5/pcsx2-dlss5.sh uninstall  # removes the launcher only
omarchy-pcsx2-dlss5 "/path/to/game.iso"            # what a Steam shortcut runs
```

Verified on 2026-10-20 with an RTX 5070, driver 615.78.08 and Burnout 3:
`ReShade.log` shows `CreateFeature(18) ... Success` and an `EvaluateFeature`
for every frame, at 60 fps with the GPU at about 58% (one pass, Model C).

## Inputs

Nothing here is committed: the files are proprietary, unofficial or not
redistributable. Install checks each pinned file against the build that was
tested and changes nothing if one is missing or different.

| Input | Default location | Override |
| --- | --- | --- |
| [PCSX2 v2.8.1](https://github.com/PCSX2/pcsx2/releases/tag/v2.8.1) `pcsx2-v2.8.1-windows-x64-Qt.7z` | `~/Downloads/pcsx2-windows/` | `PCSX2_DLSS5_DOWNLOADS` |
| Microsoft `d3dcompiler_47.dll` (64-bit; the one winetricks fetches from [mozilla/fxc2](https://github.com/mozilla/fxc2/tree/master/dll)) | `~/Downloads/pcsx2-windows/` | |
| [iMMERSE](https://github.com/martymcmodding/iMMERSE): `Shaders/MartysMods_LAUNCHPAD.fx`, `Shaders/MartysMods/`, `Textures/` (a sparse `git clone` is enough) | `~/Downloads/pcsx2-windows/iMMERSE` | `PCSX2_DLSS5_IMMERSE` |
| DLSSNR Linux v0.10.0 `dlssnr-linux.addon64` and `nvngx.dll_nrfwd.dll` | `~/Downloads/dlssnr-linux/` | `PCSX2_DLSS5_DLSSNR_DIR` |
| ReShade 6.8 add-on build `dxgi.dll` and the DLSS 5 model `nvngx_dlssnr.dll` 310.8.0 | the Pinnacle of View pack's `host64/` (see [`components/nfsu2`](../nfsu2)) | `PCSX2_DLSS5_PINNACLE_HOST` |
| Microsoft `ucrtbase.dll` | the Assetto Corsa prefix (`compatdata/244210`, vcrun2019) | `PCSX2_DLSS5_UCRTBASE` |
| `icuuc.dll` | Proton's own `icu.dll` | `PCSX2_DLSS5_PROTON` |

BIOS and games are read from `GExtended` (`GEXTENDED_MOUNT` in
`config/machine.env`). PCSX2 runs portable from `~/Games/PCSX2-Windows`
(`PCSX2_DLSS5_DIR`), with its prefix in
`~/.local/share/omarchy-gaming-setup/prefixes/pcsx2-windows` (`PCSX2_DLSS5_PREFIX`).

## Why it is set up this way

Each row was a failure under Proton, in the order they were hit:

| Problem | Fix |
| --- | --- |
| The Linux driver refuses feature 18: 610.57 answers `0xBAD0000C (OutOfDate)`, 615.78.08 `0xBAD00012 (NotImplemented)`. | DLSSNR Linux loads `nvngx_dlssnr.dll` directly through a forwarder whose name contains `nvngx.dll`. It is 64-bit only, so it cannot help 32-bit games such as NFSU2. |
| Qt does not start: `icuuc.dll` not found. | Proton's `icu.dll` exports the functions Qt6Core imports, copied in as `icuuc.dll`. |
| Black screen with sound: Wine's shader compiler fails PCSX2's vertex shader (`not yet implemented feature: Method 'Load' for structured buffers`), in Direct3D 11 and 12. | Microsoft's `d3dcompiler_47.dll`, `native,builtin`. |
| Crash when a race starts. PCSX2's symbols show `pxFailRel("Failed to allocate HashBucket Chain")` in the VIF recompiler: Wine's `_aligned_realloc` returns NULL. The trace shows it inside `user32`/`strcmp`, where Wine draws the error box. | Microsoft's `ucrtbase.dll`, `native,builtin`. |
| PCSX2 for Windows updated itself to 2.8.2 on first start. | `[AutoUpdater] CheckAtStartup = false`. |
| DLSSNR waits "for a frame". | Standalone mode needs motion vectors (iMMERSE Launchpad, enabled first in the preset) and depth (ReShade's Generic Depth, with the aspect ratio heuristic off because PCSX2's depth buffer has the PS2's shape). |
| DLSSNR waits: `depth is 1920x1344, the screen 3440x1440 -- pick the screen-sized buffer`. | The swapchain must equal the depth buffer. See below. |
| GE-Proton keeps NVAPI off. | `PROTON_FORCE_NVAPI=1` in the launcher. |

## The game window

PCSX2 renders depth at the game's native size times the internal resolution:
640x448 x 3 = 1920x1344 for most games. DLSSNR only runs when the window's
swapchain has that exact size, so the game cannot fill an ultrawide screen.
Gamescope would solve it but hides the window from Steam, which breaks Steam
Input and the PS button helper, so the launcher does it in Hyprland:

1. When the game window goes fullscreen, it is taken out of Hyprland's
   fullscreen (PCSX2 keeps its own fullscreen state, so no menu bar), floated,
   sized to the depth buffer and centered, without border, rounding or shadow.
2. `decoration.dim_around` is set to 1.0 and the window gets `dim_around`, so
   everything around it is black and it looks like a pillarboxed game.
3. The Omarchy bar is hidden (`omarchy-toggle-bar on` sets the `bar-off` flag)
   and PCSX2's main window moves to `special:pcsx2-dlss5`.
4. When PCSX2 exits, the dim value and the bar are restored.

`AspectRatio = Stretch` keeps the picture filling the swapchain so depth and
colour line up pixel for pixel; it is about 7% wider than true 4:3.

Games with another native size go in `~/Games/PCSX2-Windows/depth-sizes.conf`
(`<ROM glob> <width>x<height>`). Read the size from ReShade (Home) → Add-ons →
Generic Depth and divide by 3. PAL games (640x512) are 1536 pixels tall at 3x
and do not fit a 1440-pixel monitor; they need a lower internal resolution.

## Settings

`configure_ini.py` manages, in `PCSX2.ini`: Direct3D 12, 3x, Stretch, 16x
anisotropic, bilinear PS2 filtering, MTVU and the safe speedhacks, fast boot,
patches, game fixes, no Discord, no auto-update, start fullscreen, the BIOS and
games folders, and the pause menu on Escape (the PS button) and Share + Options.

In `ReShade.ini` it manages the shader paths, the overlay key (Home), Generic
Depth's heuristic and `StandaloneMode=1`. The tuned look (Model C, one pass,
Full model resolution, colour strength 0) is written only on the first
install, so changes made in the overlay are kept. Two passes double the
model's cost: 97% GPU, 244 W and just under 60 fps on the RTX 5070.

## Open work

- **Steam.** The PS2 shortcuts still start the Linux PCSX2. Started from a
  terminal, this launcher is not a Steam game, so the PS5 helper opens Big
  Picture on the PS button instead of sending Escape to PCSX2.
- **Depth size per game.** Neither PCSX2 nor ReShade logs the depth size, so
  games other than 640x448 need a `depth-sizes.conf` entry. The plan is for
  the launcher to try the common PS2 sizes on a game's first run, watch
  `ReShade.log` for `nr-fwd: standalone frame`, and remember the size.
- **PAL games** need a lower internal resolution to fit 1440 pixels.

## What did not work

- **Gamescope** (`-w 1920 -h 1344 -W 3440 -H 1440 -S fit`): DLSSNR ran
  fullscreen, but Steam no longer sees the game window.
- **A Hyprland window rule with `title = "^(?!PCSX2).+"`**: Hyprland's regex
  engine has no lookahead, so the rule never matched. Size and float rules also
  apply only when a window maps, before PCSX2 renames its window to the game.
- **The add-on in NFSU2's 64-bit DLSS host**: it loaded and hooked NGX, but the
  32-bit game never hands frames to the host (see [`components/nfsu2`](../nfsu2)).
