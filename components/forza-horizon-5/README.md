# Forza Horizon 5 rev lights on the G923

Steam app `1551360` under Proton. The G923's five rev lights
(`/sys/class/leds/*C26E*::RPM1`..`RPM5`) are driven by `logi-tf-sim`
(package `logi-wheel`, from `logitech-trueforce-dkms`; see
[the G923 component](../g923/README.md#trueforce-driver)). `logi-tf-sim`
does not read Forza telemetry, so this component bridges it.

```bash
./components/forza-horizon-5/forza-horizon-5.sh install    # exit Steam first
./components/forza-horizon-5/forza-horizon-5.sh check      # non-mutating
./components/forza-horizon-5/forza-horizon-5.sh dry-run
./components/forza-horizon-5/forza-horizon-5.sh uninstall  # wrapper and launch option
```

Set once in the game, by hand (FH5 stores it in its profile save, not in a
file the repo can edit): **Settings > HUD and Gameplay > Data Out** On,
**Data Out IP Address** `127.0.0.1`, **Data Out IP Port** `5300`.

## What install does

1. Installs `forza-rev-lights` as `~/.local/bin/omarchy-forza-rev-lights`.
2. With Steam closed, puts it right before `%command%` in FH5's launch
   options, after whatever is already there (the handbrake's
   `PROTON_ENABLE_HIDRAW=0x046D/0xC219` and `omarchy-match-resolution`).
   `localconfig.vdf` is backed up under
   `~/.local/state/omarchy-gaming-setup/backups/`.

Never add `PROTON_ENABLE_HIDRAW` for the G923: upstream says it kills its
force feedback. `logi-launch` does nothing for FH5 (its plan has no relay
for this appid), so it is not used here.

## How the bridge works

- FH5 sends its Data Out "Dash" packets from `127.0.0.1:5200` to port 5300:
  324 bytes, about 110 per second, all zeros in menus and while paused.
  Offsets used, little-endian: `IsRaceOn` s32 at 0, `EngineMaxRpm` f32 at 8,
  `CurrentEngineRpm` f32 at 16, `Speed` f32 (m/s) at 256, `Accel` u8 at
  315, `Brake` u8 at 316, `Gear` u8 at 319 (0 reverse).
- The wrapper starts `logi-tf-sim` if it is not running (a transient user
  service, as `logi-launch` does), then runs the bridge in a thread beside
  the game. Each packet with the race on becomes an LTFR version 2 relay
  datagram (upstream `docs/SHARED_MEMORY_RELAY.md`, 40 bytes: rpm, redline,
  throttle, gear, speed, brake) sent at up to 60 Hz to
  `logi-tf-sim` on `127.0.0.1:20780`. Menus send nothing, and `logi-tf-sim`
  darkens the lights when telemetry stops. The bridge exits with the game.
- The relay datagram is used instead of BeamNG OutGauge on udp/4444
  because OutGauge has no redline: `logi-tf-sim` would scale the lights to
  the highest RPM seen so far.
- The game id on the wire is `forza`. `logi-tf-sim` does not know it, so it
  is gated as `game.relay.*` in `~/.config/logi-wheel/tf-sim.conf`. As in
  Assetto Corsa, `logi-tf-sim` also plays simulated TrueForce vibration from
  the same telemetry; `game.relay.intensity=0` keeps only the lights.
- `/tmp/omarchy-forza-rev-lights.log` (rewritten each launch) logs every
  two seconds what was sent. Overrides: `FORZA_DATA_OUT_PORT`,
  `LOGI_TF_SIM_RELAY_PORT`, `FORZA_REV_LIGHTS_LOG`. Run the wrapper with no
  arguments to run the bridge alone.

## Verified 2026-10-24

- Data Out sends under Proton (Proton Experimental). The first session got
  no packets, for a reason not found; after relaunching the game with Data
  Out checked, they arrived, and again on the next launch. `EngineMaxRpm`
  read 7500, idle 1037, and RPM rose to 7251 under throttle.
- Synthetic packets through the bridge lit 1, 3, 4 and 5 LEDs at 1500,
  4000, 6000 and 7400 of 7500 rpm.
- In game, the user saw the rev lights follow RPM. The bridge log showed
  speed and throttle plausible (20 km/h at full throttle pulling away,
  0 km/h at idle). Only first gear was driven, so reverse, higher gears and
  brake are not yet checked against the game.
