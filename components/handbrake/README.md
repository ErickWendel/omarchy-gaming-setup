# USB handbrake (046d:c219 impostor)

The no-name USB handbrake (manufacturer "game", product "游戏手柄") reports
Logitech's RumblePad 2 / F710 DirectInput ID `046d:c219`.

```bash
./components/handbrake/handbrake.sh install    # sudo: Limine drop-in + limine-update, then reboot
./components/handbrake/handbrake.sh check      # non-mutating
./components/handbrake/handbrake.sh dry-run
./components/handbrake/handbrake.sh uninstall  # removes the drop-in, rebuilds; reboot
```

## Root cause (2026-10-12, kernel 7.2.3-arch1-3)

`hid-logitech` (both in-kernel and `new-lg4ff`) lists `c219` with the
`LG_FF2` rumble quirk. At probe it logs `missing HID_OUTPUT_REPORT 0`,
because the handbrake has no output report, and the probe fails. `hid-generic` then refuses
the device because a specialised driver matches its ID, so it stays unbound:
no `event`/`js`/`hidraw` node exists and no game or Steam can see it. This is
independent of the G29 change and was already failing at boot.

## Fix

`usbhid.quirks=0x046d:0xc219:0x400000` sets `HID_QUIRK_IGNORE_SPECIAL_DRIVER`
(`BIT(22)`) for that ID, so `hid-generic` binds it as a plain joystick.
`hid`, `usbhid`, and `hid-generic` are built into the Arch kernel, so the quirk
must be on the kernel command line; it is added as an Omarchy
`/etc/limine-entry-tool.d/` drop-in, which survives kernel and Omarchy updates.

A genuine Logitech F710 in DirectInput mode would lose rumble while this is
installed.
