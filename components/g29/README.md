# Logitech G29 in PS4 mode (issue #9)

The wheel's mode switch is stuck on PS4. This component makes it work fully on
Linux without PS3 mode, without firmware changes, and without a new driver.

```bash
./components/g29/g29.sh install    # sudo: udev rules + helper, switches a connected wheel
./components/g29/g29.sh check      # non-mutating doctor probe
./components/g29/g29.sh dry-run
./components/g29/g29.sh uninstall  # restores the pre-install state
```

## Evidence (2026-10-12, kernel 7.2.3-arch1-3, wheel bcdDevice 89.00)

- In PS4 mode the wheel enumerates as `046d:c260` with one HID interface whose
  report descriptor is DualShock-4 shaped (input report 1, output report 5,
  Sony auth feature reports `0xF0`–`0xF3`). No Logitech driver claims `c260`,
  so `hid-generic` binds it: 8-bit steering, no force feedback, no range.
- The installed `new-lg4ff-dkms-git` 0.5.0 (`hid_logitech_new`, replacing the
  in-kernel `hid-logitech`) already switches the G923 PlayStation edition out
  of PS mode by sending `f8 09 <mode> 01 01` with report ID `0x30`.
- Sending that command with the G29 mode byte (`30 f8 0a …` then
  `30 f8 09 05 01 01 00 00`) to the `c260` hidraw node makes the wheel detach
  and re-enumerate as native `046d:c24f` within a second. The Logitech driver
  then binds interface 0 with: 16-bit steering (`ABS_X` 0–65535), separate
  pedal axes, 900° range, writable gain/autocenter/range, and force feedback
  (constant, spring, damper, friction, inertia, periodic, ramp, gain,
  autocenter; 16 effect slots). Interface 1 is intentionally left unbound.
- Session ACLs (`uaccess`) already grant the logged-in user the event and
  hidraw nodes; Oversteer's packaged rule makes the sysfs controls writable.

## Design

- `71-omarchy-g29-ps4-mode.rules` matches only `hidraw` of `046d:c260` and runs
  `g29-ps4-modeswitch` on add (boot coldplug and every replug).
- The helper re-verifies `HID_ID` is USB `046d:c260` before writing and is
  volatile: power-cycling the wheel returns it to PS4 mode until udev
  switches it again. If the switch ever fails, the wheel stays a generic
  gamepad; nothing is unbound.
- An out-of-tree module is **not** required: native `c24f` is also supported
  by the in-kernel `hid-logitech` driver. `new-lg4ff` is kept because it is
  already installed and adds more effect types; `check` only reports when its
  DKMS build is missing for the running kernel.
- `60-lg4ff-userspace.rules` (copied from this machine, where it was installed
  by hand) gives the session `uinput` and the Logitech wheels' `hidraw` nodes.
  `install` puts it in `/etc/udev/rules.d` with the other rule and backs up
  any previous copy.

## Steam / Proton

Steam Input does not need to translate the wheel. If a game sees the wheel
twice or as a gamepad, disable Steam Input for that game only.
