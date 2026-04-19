# printer_data — Anycubic Vyper + Klipper

This repository holds the configuration, helper scripts, and firmware
backup needed to run Klipper on an Anycubic Vyper with a TriGorilla+
V0.0.6 board (GD32F103RET6 MCU).

## Layout

- `config/` — Klipper, Moonraker, KlipperScreen, Mainsail configs
- `sdcard/main_board_20210902_viper_v2.4.5.bin` — stock Anycubic firmware
  (the only recovery path; do not delete)
- `anycubic-VyperCE61b-klipper-firmware.mk` — Makefile with every step to
  build / flash / restore / diagnose the Klipper firmware. This is the
  primary entry point.
- `gen-stm32f103-bin.sh`, `pad-and-copy.sh`, `restore-original.sh` —
  individual shell scripts kept in sync with the Makefile

## Quick start

```bash
# Insert SD card into a USB reader on the Pi (not the printer).
make -f anycubic-VyperCE61b-klipper-firmware.mk build VERSION=v2.5.2
make -f anycubic-VyperCE61b-klipper-firmware.mk flash VERSION=v2.5.2
# Eject SD, put it in the Vyper, power-cycle. Wait ~30s for 5 beeps.
make -f anycubic-VyperCE61b-klipper-firmware.mk verify
```

Bump `VERSION` for every flash — the stock bootloader silently skips
re-flashing an already-seen filename.

## Hardware and bootloader quirks

See the header comments in
`anycubic-VyperCE61b-klipper-firmware.mk` — every non-obvious failure
mode (filename regex, file-size padding, 32 KiB flash offset, silent
USBSERIAL fallback) is documented there.

## Recovery

If a flash breaks the printer:

```bash
make -f anycubic-VyperCE61b-klipper-firmware.mk restore
# SD into Vyper, power-cycle → back to stock Anycubic UI
```
