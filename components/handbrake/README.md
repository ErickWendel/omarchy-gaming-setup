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

## Games: the "Omarchy USB Handbrake" bridge

Even when bound to `hid-generic`, SDL (used by Steam and Proton) maps
`046d:c219` to a "Logitech Cordless RumblePad 2" gamepad because of its ID and
gamepad buttons, so Proton presents an XInput-style pad and the lever axis
(`ABS_RUDDER`) is lost: Forza Horizon 5 never saw it move. Per-game fixes
failed or were rejected: `SDL_GAMECONTROLLER_IGNORE_DEVICES` hides the device
completely, and `PROTON_ENABLE_HIDRAW=0x046D/0xC219` still did not register in
FH5 and would need a launch option in every game.

`omarchy-handbrake-bridge` (system service, root) grabs the real device and
mirrors the lever to a uinput joystick, `Omarchy USB Handbrake`
(`1209:4842`, `BUS_VIRTUAL`):

- `ABS_THROTTLE`: lever position, same range as the source. A lone `ABS_X`
  is classified by neither udev nor SDL as a joystick; `ABS_THROTTLE` is.
- `BTN_TRIGGER`: pressed past 50 % travel (released below 35 %) for games
  that only bind a handbrake button. It is skipped while
  `/run/omarchy-handbrake/axis-only` exists (the service's
  `RuntimeDirectory`, world-writable with the sticky bit): a game's launch
  wrapper creates it when the game reads the axis and binds button 1 to
  something else, as NFSU2 does with nitro.

Verified with SDL 2: the virtual device is a plain joystick
(`gamecontroller=False`, 1 axis, 1 button). `72-omarchy-handbrake-hide.rules`
makes the raw `event`/`js`/`hidraw` nodes root-only (the user is in the
`input` group, so removing `uaccess` alone is not enough), so games see only
the virtual joystick. It stays present while the handbrake is unplugged.
No per-game launch options are needed.
