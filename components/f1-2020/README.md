# F1 2020 with the G923 under Proton

F1 2020 (the DX11 `F1_2020.exe`) installed to `~/Games/F1 2020`
(`F1_2020_GAME_DIR`) and run through a non-Steam shortcut on Proton
Experimental. The G923 is the Xbox edition on `logitech-trueforce-dkms` (see
[`components/g923`](../g923/README.md)).

```bash
./components/f1-2020/f1-2020.sh install    # close the game first
./components/f1-2020/f1-2020.sh check      # non-mutating
./components/f1-2020/f1-2020.sh dry-run
```

`install` is idempotent and backs up both game files it edits to
`~/.local/state/omarchy-gaming-setup/backups/f1-2020/`:

- rebinds Brake in `actionmaps/logitech_g923.xml` from `Rz` to `Z`;
- turns the game's UDP telemetry on in `hardware_settings_config.xml` (in the
  shortcut's prefix, `Documents/My Games/F1 2020/hardwaresettings/`):
  127.0.0.1, port 20778, 60 Hz, 2020 format;
- installs `omarchy-f1-2020-rev-lights` to `~/.local/bin` and enables the user
  service `omarchy-f1-2020-rev-lights.service`, so the shortcut needs no launch
  options.

## Brake held down: the car drops into reverse

The game ships a G923 action map written for Windows, where the brake is
`Rz`. Under Proton the wheel reaches the game through Wine's SDL backend
(the prefix registers it as `HID\VID_046D&PID_C26E` with no hidraw
interface). A `+dinput` trace of `joy.cpl` in the prefix shows its objects:
`X` steering, `Y` gas, `Z` brake, a `Slider` for the clutch, and the D-pad.
There is no `Rz`, and the game reads the missing axis as a fully pressed
brake: its own telemetry reported `brake=1.00` at full throttle. With the
automatic gearbox, a held brake at a standstill selects reverse, and the car
stayed there.

`install` fixes the defaults in the action map, but the game copies the
G923 mapping into the profile save the first time it sees the wheel, and
that copy wins over the file. Once a profile exists, rebind Brake (and the
clutch, if it shows up wrong) by pressing the pedal in Settings → Controls,
Vibration & Force Feedback → Logitech G923 → Edit Mapping.

To see what the game reads, check the bridge's log (`journalctl --user -u
omarchy-f1-2020-rev-lights`): every 10 s it prints the game's own gear,
throttle and brake.

## Rev lights

logi-tf-sim (package `logi-wheel`) drives the G923's rev lights from game
telemetry. It reads Codemasters/EA telemetry on udp/20777, but only the F1 22
to 25 packet formats. F1 2020 packets reach it and are ignored, so the game
sends to udp/20778 instead. `omarchy-f1-2020-rev-lights` takes the redline from
the car status packets (id 7) and RPM, gear, throttle, brake and speed from the
car telemetry packets (id 6), and sends the LTFR relay datagram to
logi-tf-sim on udp/20780. It starts logi-tf-sim if packets arrive and the
daemon is not running.

Verified on 2026-10-24 with synthetic 2020-format packets: the five
`::RPM1..5` LEDs follow RPM through the service.

logi-tf-sim does not stream simulated TrueForce to the Xbox-edition G923,
because that would silence its force feedback, so the bridge affects only
the lights.

## Force feedback

Force feedback goes through Wine's DirectInput to the driver, which supports
every effect type the game uses. The action map's defaults (strength 65,
on-track 30, rumble strips 40, off-track 20, wheel weight 5) are set in the
game's Controls menu. The game cannot set the wheel's rotation under Proton,
so the wheel stays at the driver's `range` (900°); an F1 car turns about 360°,
which Oversteer can set.

## ReShade

ReShade is not managed here. ReShade 6.8.0 runs as `dxgi.dll` in the game
folder with the "Ryan McKane F1 2020" preset (Overtake.gg). Proton
Experimental already loads the native `dxgi.dll` from the game folder, so no
override is needed.
