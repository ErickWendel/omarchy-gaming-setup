# Omarchy gaming setup

Restores this Omarchy gaming workstation (OpenRGB lighting, the Delta LCD
cooler, the Logitech G29 wheel and USB handbrake, Steam, PCSX2 and Assetto
Corsa) from a fresh Omarchy install with one command. The latest
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
| Handbrake | [`components/handbrake`](components/handbrake/README.md) | kernel quirk (Limine), raw-device hide rule, joystick bridge service |
| Hyprland | `components/hypr/install.sh` | `~/.config/hypr/gaming.lua` (Forza window rules) |
| Emulator menu entries | `components/emulators/emulators.sh` | validated `omarchy-gaming-<id>.desktop` entries from [`manifest.json`](components/emulators/manifest.json); retires EmuDeck's tab-indented entries and listed duplicates |
| Steam | `components/steam/install.sh` | single Steam autostart, `omarchy-match-resolution` launch option |
| PCSX2 | `components/pcsx2/install.sh` | `omarchy-pcsx2` wrapper, `PCSX2.ini` settings, shortcuts without Steam Input |
| Assetto Corsa | [`components/assetto-corsa`](components/assetto-corsa/README.md) | Content Manager, CSP fonts, Proton 9.0, launch wrapper, prefix components |
| NFS Underground 2 | [`components/nfsu2`](components/nfsu2/README.md) | Pinnacle of View files, patched DXVK, Khronos `vulkan-1.dll`, ReShade Vulkan layer and prefix overrides |
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
