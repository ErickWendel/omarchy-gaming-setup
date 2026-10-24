# Omarchy gaming setup

Restores this Omarchy gaming workstation (OpenRGB lighting, the Delta LCD
cooler, the Logitech G29 wheel and USB handbrake, Steam, PCSX2, Assetto
Corsa and NFS Underground 2) from a fresh Omarchy install with one command. The latest
real-machine results are in [`STATUS.md`](STATUS.md); read it first when
resuming work.

This is a personal setup for one machine: its hardware, its `GExtended`
games disk and its file locations. To use it on another machine, copy
`config/machine.example.env` to `config/machine.env`, set your own values,
and run `./setup.sh --dry-run` first.

Related repositories, installed by this one:

- [ps5-steam-big-picture](https://github.com/ErickWendel/ps5-steam-big-picture):
  cloned automatically at the commit pinned in `config/machine.example.env`.
- [delta-cw360lcd-linux-driver](https://github.com/ErickWendel/delta-cw360lcd-linux-driver):
  builds the private Delta runtime archive (see below).

ROMs, BIOS files, proprietary Delta binaries, Content Manager, Steam
userdata, credentials and logs are never committed. `tests/privacy-test.sh`
checks the ignore rules, the working tree and the Git history.

## What this adds to Omarchy

A fresh Omarchy install did not support this hardware, or these games, out of
the box. Each row is something that was missing or broken on stock Omarchy
and what this repository installs to fix it. Details and evidence are in each
component's README and in [`STATUS.md`](STATUS.md).

### Drivers and kernel

| Problem on stock Omarchy | What this repository adds |
| --- | --- |
| **Logitech G29 stuck in PS4 mode** shows up as `046d:c260`, a generic gamepad: 8-bit steering, no force feedback, no wheel range. | A udev rule and helper that switch it to native mode (`046d:c24f`) on every boot and replug, plus the optional AUR `new-lg4ff-dkms-git` driver and Oversteer for range and gain ([`components/g29`](components/g29/README.md)). |
| **Logitech G923 Xbox edition** powers up in Xbox mode (`046d:c26d`), a vendor-class device Linux cannot use; usb_modeswitch has no entry for it. | `logitech-trueforce-dkms` (AUR) switches it to PC mode (`046d:c26e`) on every boot and replug, and its own force engine gives force feedback with the G29's full effect set ([`components/g923`](components/g923/README.md)). |
| **USB handbrake** (`046d:c219`, a Logitech ID) fails to bind: `hid-logitech` expects a rumble report it does not have, so no input device exists at all. | The kernel option `usbhid.quirks=0x046d:0xc219:0x400000` through a Limine drop-in, so `hid-generic` binds it ([`components/handbrake`](components/handbrake/README.md)). |
| **Handbrake lever invisible to games**: SDL maps the ID as a RumblePad 2 gamepad and drops the lever axis, so Steam and Proton never see it. | `omarchy-handbrake-bridge`, a service that hides the raw device and exposes a plain "Omarchy USB Handbrake" joystick. |
| **Delta CW360LCD cooler screen** has only a Windows app. | The Linux build of Delta Center from [delta-cw360lcd-linux-driver](https://github.com/ErickWendel/delta-cw360lcd-linux-driver), a USB access udev rule, and a hidden login service (`scripts/delta.sh`). |
| **Packages** the components need are not installed by default. | `openrgb`, `steam-devices` (controller access), `protontricks`, `usb_modeswitch` and `logitech-trueforce-dkms` (G923), `python-evdev` and `python-vdf` (`scripts/packages.sh`). |

### Desktop and Steam

| Problem on stock Omarchy | What this repository adds |
| --- | --- |
| **Renamed autostart files still run**: systemd's autostart generator launches every file in `~/.config/autostart`, so OpenRGB and Delta started twice, and Delta opened its window. | Retired entries are moved out of that folder, and both apps run as user services (`openrgb.service`, `delta-center.service`). |
| **Steam started twice** at login. | A single Steam autostart (`components/steam/install.sh`). |
| **The PS button does nothing** on the desktop. | The [ps5-steam-big-picture](https://github.com/ErickWendel/ps5-steam-big-picture) helper: PS opens Big Picture when no game runs. |
| **Fullscreen is lost when a window closes**: Hyprland does not give it back to the window underneath, such as Big Picture after a game or a game after its launcher. | The `fullscreen-restore` user service ([`components/hypr`](components/hypr)). |
| **Black screen in Proton games set to a non-native resolution**: Proton's fake mode change adds an empty fullscreen window over the game. | `omarchy-match-resolution`, a Steam launch option that writes the current monitor's resolution into the game's settings before launch, plus Forza Horizon 5 window rules (`components/hypr/gaming.lua`). |
| **Emulators missing from the app launcher**: EmuDeck writes menu entries indented with tabs, which Omarchy's launcher skips. | Validated menu entries generated from [`manifest.json`](components/emulators/manifest.json). |
| **PCSX2 controllers misrouted**: PCSX2 runs as a native Wayland window, which Steam cannot see, so Steam sends controller input to Big Picture behind the game. | The `omarchy-pcsx2` wrapper forces XWayland; its shortcuts run without Steam Input, with pause-menu hotkeys on the controller (`components/pcsx2`). |

### Games under Proton

| Problem on stock Omarchy | What this repository adds |
| --- | --- |
| **Assetto Corsa with Content Manager and Custom Shaders Patch (CSP)**: CSP fails to start on Proton 10, crashes without the Segoe UI font, and Steam refuses to relaunch while Content Manager's Wine processes stay alive. | A Proton 9.0 prefix with the needed Windows components, the CSP fonts, a launch wrapper that cleans up on exit, and a window rule for Content Manager ([`components/assetto-corsa`](components/assetto-corsa/README.md)). |
| **G923 rev lights in Forza Horizon 5**: `logi-tf-sim` lights them from telemetry but does not read Forza's Data Out packets. | A launch wrapper that converts Data Out to the driver's relay datagram while the game runs ([`components/forza-horizon-5`](components/forza-horizon-5/README.md)). |
| **NFS Underground 2 with Pinnacle of View** loads ReShade as a Windows Vulkan layer, which Wine's built-in `vulkan-1.dll` ignores. | The Khronos `vulkan-1.dll`, a patched DXVK and the ReShade layer registered in the prefix ([`components/nfsu2`](components/nfsu2/README.md)). |
| **DLSS 5 in PS2 games**: the Linux NVIDIA driver answers NGX feature 18 with `NotImplemented`, and Windows PCSX2 under Proton has no Qt ICU, a broken shader compiler and a crashing `_aligned_realloc`. | Windows PCSX2 2.8.1 with the DLSSNR Linux add-on, Microsoft `d3dcompiler_47.dll` and `ucrtbase.dll`, and a launcher that sizes the game window to the depth buffer ([`components/pcsx2-dlss5`](components/pcsx2-dlss5/README.md)). |

## Restore the system

### 1. Before you run setup

On the fresh Omarchy install:

1. Log in to the Hyprland desktop (setup starts user services in the session).
2. Install Steam and sign in, enable **Settings → Interface → Run Steam when
   my computer starts**, and install the games you play (Forza Horizon 5,
   Assetto Corsa). Setup works without them, but Steam modules only configure
   what is installed.
3. Copy the private files back. Setup reads them from these paths:

   | File | Where | Used by |
   | --- | --- | --- |
   | Delta runtime `delta-center-linux-compat-2.0.11-x64.tar.gz` | any path, passed with `--delta-archive` | Delta |
   | PCSX2 AppImage, made executable | `~/Applications/pcsx2-Qt.AppImage` | PCSX2 |
   | PS2 BIOS, ROMs, other emulators | where PCSX2/EmuDeck expect them (usually `GExtended`) | PCSX2 |
   | Content Manager | `~/Downloads/content-manager/Content Manager.exe` (or `AC_CM_EXE`) | Assetto Corsa |
   | CSP fonts | `~/Downloads/asseto/ac-fonts.zip` (or `AC_FONTS_ZIP`) | Assetto Corsa |
   | Pinnacle of View, extracted ([Nexus](https://www.nexusmods.com/needforspeedunderground2/mods/111?tab=description)) | `~/Downloads/nfsu2/PinancleofView*/` | NFS Underground 2 |
   | LunarG Vulkan Runtime components zip | `~/Downloads/nfsu2/vulkan-runtime-components.zip` | NFS Underground 2 |
   | PCSX2 2.8.1 for Windows, `d3dcompiler_47.dll`, iMMERSE | `~/Downloads/pcsx2-windows/` | PCSX2 with DLSS 5 |
   | DLSSNR Linux add-on and forwarder | `~/Downloads/dlssnr-linux/` | PCSX2 with DLSS 5 |

   Rebuild the Delta archive from the driver repository if you lost it; its
   README explains how (`npm run assemble:linux`, then `tar`).

### 2. Run setup

```bash
git clone https://github.com/ErickWendel/omarchy-gaming-setup.git ~/Downloads/projects/omarchy-gaming-setup
```

```bash
cd ~/Downloads/projects/omarchy-gaming-setup
```

```bash
./setup.sh --delta-archive /path/to/delta-center-linux-compat-2.0.11-x64.tar.gz
```

Setup asks for your sudo password, installs the missing packages, and closes
Steam before it edits Steam's files. It prints `Modules that need attention`
for anything it could not finish, such as a missing private file, game or
device; the other modules still install. Fix what it reports and run
`./setup.sh` again: it is idempotent, and modules already in place make no
changes. Once the Delta runtime is installed, later runs no longer need
`--delta-archive`.

To preview the changes first, run `./setup.sh --dry-run`.

### 3. Reboot and check

The handbrake's kernel option and the login services take effect after a
reboot. Then:

```bash
./setup.sh --check
```

It prints `OK`/`WARN`/`FAIL` lines for each module and exits nonzero while
anything needs attention, ending with the modules to fix.

### 4. One-time manual steps

These cannot be scripted. Do them once, then rerun `./setup.sh`:

- **PCSX2**: start it once (`~/.local/bin/omarchy-pcsx2`) so it creates
  `PCSX2.ini`, and set the BIOS folder. Recreate the emulator shortcuts with
  Steam ROM Manager/EmuDeck; setup then points them at the wrapper.
- **Emulators**: EmuDeck writes its menu entries with every line indented by
  a tab, so Omarchy's launcher does not list them. Setup replaces them with
  validated entries whose drive launchers are resolved under `GExtended` by
  UUID; entries whose launcher is missing (disk not mounted) are skipped.
  Rerun `./setup.sh` after an EmuDeck update recreates the broken entries.
  Steam shortcuts are not generated from the manifest yet.
- **Assetto Corsa**: create the Proton prefix with GE-Proton9-20 as described
  in [`components/assetto-corsa/README.md`](components/assetto-corsa/README.md#new-prefix-manual-once).
  For the DualSense, disable Steam Input for the game and pick the Xbox 360
  preset in Content Manager (same README).
- **Forza Horizon 5**: select Manual with Clutch in the game to see the G29
  gear bindings.
- **Multiple Steam accounts**: set `STEAM_USER_ID` in `config/machine.env`
  (copy `config/machine.example.env`).

Then verify the hardware with [`TESTING.md`](TESTING.md).

## Modules

`./setup.sh` runs these in order. Each also runs alone, and most accept
`install`, `check` and `dry-run`:

| Module | Script | What it manages |
| --- | --- | --- |
| Packages | `scripts/packages.sh` | `openrgb`, `steam`, `steam-devices`, `protontricks`, `python-evdev`, `python-vdf` and tools; optional AUR `new-lg4ff-dkms-git` and `oversteer` |
| OpenRGB | `scripts/openrgb.sh` | `static-green` profile, `openrgb.service`, retires XDG autostart |
| Delta | `scripts/delta.sh` | runtime from the archive, USB udev rule, hidden `delta-center.service` |
| G29 wheel | [`components/g29`](components/g29/README.md) | udev switch from PS4 mode to native mode, wheel access rule |
| G923 wheel (Xbox edition) | [`components/g923`](components/g923/README.md) | `logitech-trueforce-dkms` options (force engine) and a check that it switched the wheel from Xbox mode to PC mode |
| Handbrake | [`components/handbrake`](components/handbrake/README.md) | kernel quirk (Limine), raw-device hide rule, joystick bridge service |
| Hyprland | `components/hypr/install.sh` | `~/.config/hypr/gaming.lua` (Forza window rules) |
| Emulator menu entries | `components/emulators/emulators.sh` | validated `omarchy-gaming-<id>.desktop` entries from [`manifest.json`](components/emulators/manifest.json); retires EmuDeck's tab-indented entries and listed duplicates |
| Steam | `components/steam/install.sh` | single Steam autostart, `omarchy-match-resolution` launch option |
| PCSX2 | `components/pcsx2/install.sh` | `omarchy-pcsx2` wrapper, `PCSX2.ini` settings, shortcuts without Steam Input |
| Assetto Corsa | [`components/assetto-corsa`](components/assetto-corsa/README.md) | Content Manager, CSP fonts, Proton 9.0, launch wrapper, prefix components |
| Forza Horizon 5 | [`components/forza-horizon-5`](components/forza-horizon-5/README.md) | `omarchy-forza-rev-lights` launch option: Data Out telemetry to `logi-tf-sim` for the G923 rev lights |
| NFS Underground 2 | [`components/nfsu2`](components/nfsu2/README.md) | Pinnacle of View files, patched DXVK, Khronos `vulkan-1.dll`, ReShade Vulkan layer and prefix overrides |
| PCSX2 with DLSS 5 | [`components/pcsx2-dlss5`](components/pcsx2-dlss5/README.md) | Windows PCSX2 2.8.1 in its own prefix, ReShade with DLSSNR Linux and iMMERSE Launchpad, Microsoft runtime DLLs, `omarchy-pcsx2-dlss5` launcher |
| Steam helper | `components/steam/helper.sh` | pinned `ps5-steam-big-picture` monitor service |

`./setup.sh --check` also reports whether the `GExtended` disk is mounted
read-write at `GEXTENDED_MOUNT` and whether the user desktop entries
validate. Setup never formats, repairs or remounts a filesystem.

Safety rules shared by every module:

- User files are backed up under `~/.local/state/omarchy-gaming-setup/backups`
  before they are replaced. System files (`/etc`, `/usr/local`) are installed
  with sudo; the G29 and handbrake modules have an `uninstall` action.
- A missing optional device, game or private file fails only its own module.
- Retired autostart entries are moved out of `~/.config/autostart`, because
  systemd's XDG autostart generator launches every file there, whatever its
  name.
- Nothing under `/usr/share/omarchy` is edited.

## Tests

```bash
for test in tests/*.sh; do bash "$test"; done
```

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

The shell tests run against a temporary home directory and fake system
commands, so they never touch the real machine.

## Backlog

The original issue bodies are kept under [`planning/issues`](planning/issues).
The storage investigation includes a separately confirmed, destructive
reformat only after hardware diagnostics and a checksum-verified copy to
another local disk; normal setup and check runs never do this.
`scripts/apply-fast-fixes.sh` is kept for older notes and now runs
`./setup.sh`.

## License

[MIT](LICENSE)
