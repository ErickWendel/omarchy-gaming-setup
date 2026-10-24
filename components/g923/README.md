# Logitech G923 Racing Wheel for Xbox One and PC

The Xbox edition powers up in Xbox mode, where Linux cannot use it. This
component switches it to PC mode on every boot and replug.

```bash
./scripts/packages.sh install        # adds usb_modeswitch
./components/g923/g923.sh install    # sudo: usb_modeswitch config + udev rule, switches a connected wheel
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
  entry, so `install` adds `/etc/usb_modeswitch.d/046d:c26d` and
  `41-omarchy-g923-xbox-mode.rules`. The rule runs the package's udev helper,
  which starts `usb_modeswitch@.service`; the dispatcher reads `/etc` first.
- The AUR package `logitech-g923-xbox-udev` (1-1, 2023) ships the same
  `046d:c26d` config with the same `0f00010142` message. This component keeps
  its own copy so `check`, backups and `uninstall` cover it; do not install
  both. `logitech-g923-xbox-ffb-udev` grants the `c26e` hidraw node to the
  `input` group; the access rule below does the same through `uaccess`.
- In PC mode the in-kernel `hid-logitech-hidpp` driver binds `c26e` (alias
  `hid:b0003g*v0000046Dp0000C26E`) and provides force feedback and a writable
  `range`. `new-lg4ff` does **not** support this edition, so the extra
  G29-only attributes (`combine_pedals`, `gain`, `autocenter`) do not exist.
- Oversteer knows `c26e` and its packaged rule makes `range` and the LEDs
  writable. The G29 component's `60-lg4ff-userspace.rules` also grants the
  session the wheel's `hidraw` node.

Verified 2026-10-23 with the wheel connected: the journal shows
`switch device 046d:c26d`, the wheel comes back as `046d:c26e`, `check`
passes and Oversteer recognises it. Interface 0 carries the wheel
(`ABS_X` 0–65535 steering; `ABS_Y`/`ABS_Z`/`ABS_RZ` 0–255 gas, brake,
clutch, all 255 when released; 23 buttons; 900° range). Interface 1 is a
second HID++ node with no input, which `check` skips. Force feedback offers
constant, spring, damper, periodic, rumble, gain and autocenter; there is no
friction, inertia or ramp as new-lg4ff gives the G29.

NFS Underground 2 works with it through the wheel wrapper; see
[its G923 section](../nfsu2/README.md#g923-xbox-edition).

The switch is volatile and writes no firmware: power-cycling the wheel
returns it to Xbox mode until udev switches it again. If the switch fails,
the wheel stays unusable and nothing else changes; `check` points at the
`usb_modeswitch@` journal.

## Not covered yet

- Game bindings made for the G29 (Forza Horizon 5, Assetto Corsa) need to be
  redone for the G923; games see it as a different device.
