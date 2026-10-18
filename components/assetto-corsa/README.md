# Assetto Corsa (Content Manager + CSP + ReShade under Proton)

Steam app `244210`, launched through Content Manager, with Custom Shaders
Patch (CSP) 0.3.0-preview140, Pure 3.10 and an optional ReShade preset.

```bash
./components/assetto-corsa/assetto-corsa.sh install    # exit Steam first
./components/assetto-corsa/assetto-corsa.sh check      # non-mutating
./components/assetto-corsa/assetto-corsa.sh dry-run
./components/assetto-corsa/assetto-corsa.sh uninstall  # wrapper, window rule, original exe
```

`install` is idempotent, and its steps run independently: a missing download
only fails its own step. It never deletes the Proton prefix. Inputs that are
not in this repository (third-party or proprietary) are read from local files:

| Input | Default | Override |
| --- | --- | --- |
| Content Manager | `~/Downloads/content-manager/Content Manager.exe` | `AC_CM_EXE` |
| CSP fonts (`system/segoeui.ttf`, from acstuff) | `~/Downloads/asseto/ac-fonts.zip` | `AC_FONTS_ZIP` |

## What install does

1. Installs `ac-steam-wrapper` to `~/.local/bin`.
2. Installs `assettocorsa.lua` to `~/.config/hypr` and requires it from
   `hyprland.lua`.
3. Puts Content Manager in place of `AssettoCorsa.exe`, keeping the original as
   `AssettoCorsa_original.exe`. This happens once only: Content Manager updates itself in place.
   Verifying the game files in Steam restores the original exe; rerun install.
4. Unpacks the CSP fonts into `content/fonts/system`.
5. With Steam closed, sets the Steam launch options and the Proton 9.0
   (`proton_9`) compatibility tool. Both files are edited line by line and
   backed up under `~/.local/state/omarchy-gaming-setup/backups`:

   ```
   WINEDLLOVERRIDES="dxgi=n,b;dwrite=n,b" PROTON_USE_XALIA=0 ~/.local/bin/ac-steam-wrapper %command%
   ```

6. Installs `vcrun2019 d3dcompiler_43 d3dx11_43 d3dcompiler_47 corefonts
   dotnet48` into the prefix with protontricks if `winetricks.log` lacks
   them, then sets the prefix to `win10`.

## New prefix (manual, once)

CSP only patched the game in a prefix created by GE-Proton9-20 and then run
with Proton 9.0 ([GE-Proton #514](https://github.com/GloriousEggroll/proton-ge-custom/issues/514#issuecomment-4453661939),
[assettocorsa-linux-setup #68](https://github.com/sihawido/assettocorsa-linux-setup/issues/68)).
Running `proton run wineboot` outside Steam hung on
`rundll32 setupapi,InstallHinfSection Wow64Install`, so let Steam create it:

1. Install Proton 9.0 (`steam steam://install/2805730`) and GE-Proton9-20
   (release tarball, checksum-verified, into
   `~/.local/share/Steam/compatibilitytools.d`).
2. Exit Steam. Move the old prefix aside:
   `mv steamapps/compatdata/244210 steamapps/compatdata/244210.bak`.
3. Set the game's compatibility tool to GE-Proton9-20, start Steam, press Play
   once, and close Content Manager once it opens.
4. Exit Steam and run `install`. It switches the game to Proton 9.0 and installs the prefix
   components.
5. Copy `drive_c/users/steamuser/Documents/Assetto Corsa` and
   `drive_c/users/steamuser/AppData/Local/AcTools Content Manager` from the
   old prefix, and symlink `drive_c/Program Files (x86)/Steam/config/loginusers.vdf`
   to `~/.local/share/Steam/config/loginusers.vdf`.

## Root causes (2026-10-12, AC 1.16.4, CSP 0.3.0-preview140)

- **"Failed to patch Assetto Corsa: Can't find ACClient::…"**: the game version was
  correct. CSP's log showed `Running with Wine` → `Failed to initialize` on
  UMU-Proton-10.0-4. CSP never ran, so Pure and the AC Vision PP filter never
  applied either, and the ReShade preset sat on top of the vanilla image,
  which looked washed out. Fixed by the Proton 9.0 prefix above.
- **CSP crash `Font "C:\windows\Fonts\segoeui.ttf" is missing`**: Wine has no
  Segoe UI. CSP also looks in `content/fonts/system`.
- **CSP "Generic error" crash**: the crash report showed `OS-Version: 6.1.7601`
  (Windows 7), left behind by the .NET installers. Set the prefix to `win10`.
- **Steam refuses to launch (`AppError_16`, "WaitingPrevProcess")**: the
  previous launch options ran Proton through `sh -c '… proton waitforexitandrun "Content Manager.exe"' %command%`,
  which bypassed Steam's reaper. After Content Manager closed, its wineserver
  (with `winedevice.exe` and `xalia.exe`) stayed alive. Content Manager now
  replaces `AssettoCorsa.exe`, so `%command%` launches it, and the wrapper
  kills the prefix's wineserver on exit.
- **Content Manager disappears after a race**: it hides to the tray during a
  race and comes back as a tiled window 22–56 px wide. The window rule floats
  it at 1600×900. It matches on title, so the race window is unaffected.

## DualSense (CSP Gamepad FX)

Checked on 2026-10-17 with the
[DualSense Gamepad Assist](https://github.com/Adudumax/DualSense-Gamepad-Assist)
Gamepad FX script. Copy its `apps` and `extension` folders into the game folder.

- **Steam Input off** for Assetto Corsa (Properties → Controller → Disable
  Steam Input). Proton 9 then passes the DualSense through as raw HID, so
  Content Manager lists it as `Wireless Controller`. That name is expected.
- **Content Manager → Settings → Assetto Corsa → Controls**: Input method
  Gamepad, preset **Xbox 360**. CSP still finds the DualSense underneath, and
  the script works over USB and Bluetooth. CSP says the haptics need USB.
- **CSP → Gamepad FX**: Active; Gamepad script Active with `DualSense Gamepad
  Assist`; DualShock/DualSense integration Active with "Detect PS5 DualSense
  automatically".
- With Steam Input on, Steam hides the pad behind a virtual Xbox controller.
  Content Manager then logs `Device Wireless Controller is missing, using
  placeholder`, the throttle does nothing, the stick moves the mouse, and the
  DualSense features are gone.
- To debug detection, add `[BASIC]` `DEBUG=1` to
  `Documents/Assetto Corsa/cfg/extension/gamepad_fx.ini` in the prefix, then
  read `Documents/Assetto Corsa/logs/custom_shaders_patch.log`.

## ReShade

- Install ReShade into the game folder for `acs.exe` with DirectX 10/11/12.
  It writes `dxgi.dll`; the `dxgi=n,b` override makes Proton load it.
- `ReShade.ini` stores the preset path from the Wine session that ran the
  installer (`C:\users\<you>\…`). That path does not exist in the game's
  prefix, so ReShade shows the preset name with every effect unticked. Point
  `PresetPath` at the file through `Z:`, e.g.
  `Z:\home\<you>\Downloads\asseto\AC Vision Reality 1.4.7 Unreal V2\AC Vision Unreal V2.ini`.
- Ticking or unticking effects in the in-game overlay while CSP runs crashes the
  game with a CSP "Generic error"; a full race without touching the overlay
  does not. Change the `Techniques=` line of the preset with the game closed.
  With Auto Save on, unticked effects are saved to the preset.
