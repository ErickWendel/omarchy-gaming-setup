# Logitech G923 Racing Wheel for Xbox One and PC

The Xbox edition powers up in Xbox mode, where Linux cannot use it. The
`logitech-trueforce-dkms` package switches it to PC mode on every boot and
replug and drives it with its force engine; this component sets the driver up
and checks the result.

```bash
./scripts/packages.sh install        # adds usb_modeswitch and logitech-trueforce-dkms (AUR)
./components/g923/g923.sh install    # sudo: driver options, switches a connected wheel
./components/g923/g923.sh check      # non-mutating doctor probe
./components/g923/g923.sh dry-run
./components/g923/g923.sh uninstall  # restores the pre-install state
```

## How it works (2026-10-23, kernel 7.2.8-9-omarchy)

- In Xbox mode the wheel enumerates as `046d:c26d`, a vendor-class USB device
  with no HID interface. Sending the HID++ message `0f00010142` (the one
  usb-modeswitch-data ships for the G920, `046d:c261`) makes it re-enumerate
  as `046d:c26e`.
- usb_modeswitch 2.6.2 (usb-modeswitch-data 20251207) has no `046d:c26d`
  entry. `logitech-trueforce-dkms` ships
  `/usr/lib/udev/rules.d/73-logitech-xbox-modeswitch.rules`, which runs
  `logi-wheel-modeswitch` through `systemd-run`. That releases any driver
  holding the wheel and sends `0f00010142` with `usb_modeswitch`, so
  `usb_modeswitch` must stay installed. `check` requires both.
- Until 2026-10-24 this component installed its own copy of the switch
  (`/etc/usb_modeswitch.d/046d:c26d` and `41-omarchy-g923-xbox-mode.rules`).
  Both switches then ran on every plug-in, so the package's is the only one
  now. `install` and `uninstall` remove the old files, restoring any backup.
  Without the package the wheel stays in Xbox mode.
- The AUR packages `logitech-g923-xbox-udev` (the same config) and
  `logitech-g923-xbox-ffb-udev` are not needed; do not install them beside
  `logitech-trueforce-dkms`.
- In PC mode the in-kernel `hid-logitech-hidpp` driver binds `c26e` (alias
  `hid:b0003g*v0000046Dp0000C26E`) and provides force feedback and a writable
  `range`. This is the fallback; see [TrueForce driver](#trueforce-driver)
  for what drives it now. `new-lg4ff` does **not** support this edition, so the extra
  G29-only attributes (`combine_pedals`, `gain`, `autocenter`) do not exist.
- Oversteer knows `c26e` and its packaged rule makes `range` and the LEDs
  writable. The G29 component's `60-lg4ff-userspace.rules` also grants the
  session the wheel's `hidraw` node.

Verified 2026-10-23 with the wheel connected: the journal shows
`switch device 046d:c26d`, the wheel comes back as `046d:c26e`, `check`
passes and Oversteer recognises it. Interface 0 carries the wheel
(`ABS_X` 0–65535 steering; `ABS_Y`/`ABS_Z`/`ABS_RZ` 0–255 gas, brake,
clutch, all 255 when released; 23 buttons; 900° range). Interface 1 is a
second HID++ node with no input, which `check` skips. On
`hid-logitech-hidpp`, force feedback offers constant, spring, damper,
periodic, rumble, gain and autocenter; there is no friction, inertia or ramp
as new-lg4ff gives the G29 (the TrueForce driver's engine adds them).

Games, verified by the user on 2026-10-23 and again on the TrueForce engine:

- NFS Underground 2 through the wheel wrapper; see
  [its G923 section](../nfsu2/README.md#g923-xbox-edition).
- Assetto Corsa: `controls.ini` in the AC prefix binds gas axis 1, brake 2,
  clutch 3, with `FF_GAIN=1.4` and `FILTER_FF=0.05`. Set in game, not by the
  repo.
- Forza Horizon 5: bound in game, with no `PROTON_ENABLE_HIDRAW` for the
  G923.

The switch is volatile and writes no firmware: power-cycling the wheel
returns it to Xbox mode until udev switches it again. If the switch fails,
the wheel stays unusable and nothing else changes; `check` points at
`journalctl -b -t logi-wheel-modeswitch`.

## TrueForce driver

Since 2026-10-24 the wheel runs on
[logitech-trueforce-linux-driver](https://github.com/mescon/logitech-trueforce-linux-driver)
(AUR `logitech-trueforce-dkms` 0.42.6-1, module `hid-logitech-dd`, driver
name `logitech-dd`). The user compared it with `hid-logitech-hidpp` in NFS
Underground 2, Assetto Corsa and Forza Horizon 5 and found force feedback
clearly better.

- **Force engine.** `logitech-trueforce.conf`, installed to
  `/etc/modprobe.d`, sets `g923_xbox_dd_engine=1`. The driver then computes
  the effects itself instead of handing them to the wheel's firmware
  (HID++ 0x8123). That adds friction, inertia and ramp, the same set
  new-lg4ff gives the G29. Without the option the driver uses the firmware
  path, which advertises the same effects as `hid-logitech-hidpp` and adds
  nothing but the rev lights. Upstream marks the engine experimental (a
  faint motor whine, issue #85).
- **Pedals as before.** The driver turns the G923's pedals round on evdev
  by default (0 released). `g923_pedal_invert=N` keeps them at 255
  released, so the NFSU2 (`pedals_to = -Z`), Assetto Corsa and Forza
  bindings made on `hid-logitech-hidpp` stay valid.
- **Load-time options in the initramfs.** The package's pacman hook writes
  `/etc/mkinitcpio.conf.d/logitech-trueforce.conf` so `hid-logitech-dd`
  loads before `hid-logitech-hidpp` at boot, and the `modconf` hook copies
  `/etc/modprobe.d` into the image. `install` therefore regenerates the
  initramfs (`logi-wheel-initramfs --force`) whenever the options change.
  A changed option needs the module reloaded with the wheel unplugged:
  `sudo modprobe -r hid-logitech-dd && sudo modprobe hid-logitech-dd`.
- **Unbinding hazard.** The package's
  `72-logitech-g923-rebind.rules` takes `c26e` from `hid-logitech-hidpp`
  when that driver wins the bind. `hid-logitech-hidpp` can oops if it is
  unbound while a program holds the wheel open (upstream #90; Chrome's
  Gamepad API does, as well as Steam). The first switch was done with the
  wheel unplugged: `hid-logitech-hidpp` reloaded so `hid-logitech-dd`
  registers first, then the wheel plugged back in. Unplugging the wheel
  under `hid-logitech-hidpp` with Chrome open gave a kernel WARNING
  (`kernfs: can not remove 'range'`), not an oops.
- **G29 unaffected.** The package's `/etc/modprobe.d/hid-logitech-dd.conf`
  blacklists `hid-logitech-new`. `new-lg4ff-dkms-git` installs its module as
  `updates/dkms/hid-logitech.ko` (modprobe name `hid_logitech`), so that line
  matches nothing here and `hid_logitech_new` still loads. The driver does
  not claim `c24f`.
- **Stuck TrueForce stream (seen once, 2026-10-24).** The engine routes
  vibration effects through the TrueForce stream ("TrueForce texture channel
  ready" in `dmesg`). After the games, the driver logged
  `TrueForce wind-down teardown pair could not be queued after 1000 ticks;
  abandoning the stream`. For the next two minutes every force-feedback
  command to interface 1 failed (`error -71, 195720 errors`), until the wheel
  re-enumerated. Replugging the wheel clears it. If force feedback dies
  in game, look for those lines in `journalctl -k`; if it happens again,
  report it upstream.
- **No `PROTON_ENABLE_HIDRAW`** for this wheel: upstream says it kills its
  force feedback.
- **Rev lights and simulated TrueForce in Assetto Corsa.** The rev lights
  (`::RPM1`..`::RPM5`) work: a manual sweep through their `brightness` files
  lit them on 2026-10-24. In a game they need RPM from telemetry, which
  `logi-tf-sim` (package `logi-wheel`) reads. Of these games only Assetto
  Corsa publishes telemetry it reads, so `components/assetto-corsa` puts
  `logi-launch` in AC's launch options, and that also turns on simulated
  TrueForce vibration (`intensity` in `~/.config/logi-wheel/tf-sim.conf`,
  default 30; 0 keeps only the lights). NFSU2 and Forza Horizon 5 stay dark.

Baseline on `hid-logitech-hidpp` for comparison: the same axes, and the
effects listed above without friction, inertia or ramp.

To go back, run `./components/g923/g923.sh uninstall`, then
`omarchy-pkg-remove logitech-trueforce-dkms logi-wheel`. Delete
`/etc/mkinitcpio.conf.d/logitech-trueforce.conf` (the package does not own
it) and run `sudo mkinitcpio -P`. The wheel then needs its own Xbox-mode
switch again: restore `046d:c26d` and `41-omarchy-g923-xbox-mode.rules` from
this component's git history (before 2026-10-24).

## Not covered yet

- Simulated TrueForce and the rev lights (see above).
- The game bindings live in each game's own config and are not installed by
  the repo.
