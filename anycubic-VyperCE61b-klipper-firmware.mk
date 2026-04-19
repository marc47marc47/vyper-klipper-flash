# ============================================================================
#  Anycubic Vyper (CE61b) / TriGorilla+ V0.0.6  ->  Klipper firmware
#  Verified working 2026-04-19, Klipper v0.13.0-320-gc80324946
#
#  Usage:
#    make -f anycubic-VyperCE61b-klipper-firmware.mk help
#    make -f anycubic-VyperCE61b-klipper-firmware.mk build
#    make -f anycubic-VyperCE61b-klipper-firmware.mk flash
#    make -f anycubic-VyperCE61b-klipper-firmware.mk restore
# ============================================================================

# ----------------------------------------------------------------------------
# HARDWARE FACTS (silkscreen + chip markings, confirmed 2026-04-19)
# ----------------------------------------------------------------------------
# Board        : Anycubic TriGorilla+ V0.0.6  (Marlin: BOARD_TRIGORILLA_V006)
# MCU          : GD32F103RET6  (GigaDevice clone of STM32F103RE)
#                Cortex-M3, 108MHz capable (Klipper runs it at 72MHz),
#                512KB flash, 64KB SRAM, LQFP64
# USB-serial   : CH340 (QinHeng 1a86:7523) wired to USART1 (PA10/PA9)
# Crystal      : 8MHz HSE
# Bootloader   : Anycubic stock, resides at 0x08000000, size 32KiB
#                Flashes .bin files from SD card root, jumps to 0x08008000
# Screen       : DWIN-style, proprietary protocol; becomes non-functional
#                under Klipper (use KlipperScreen or Mainsail web UI instead)

# ----------------------------------------------------------------------------
# BOOTLOADER QUIRKS (learned the hard way - all silent failures)
# ----------------------------------------------------------------------------
# 1. Filename MUST match regex:  main_board_YYYYMMDD_viper_vN.N.N.bin
#    - "viper" is literally in the name (not "vyper"). Stock filename was
#      main_board_20210902_viper_v2.4.5.bin.
#    - Version suffixes like "-klipper" or "-usart1" are REJECTED silently.
#    - Only ONE main_board_*.bin on the SD at a time; the bootloader picks
#      nondeterministically if multiple match.
#
# 2. Date + version must be NEWER than anything previously flashed, otherwise
#    bootloader silently skips.  Use a far-future date (e.g. 20261231) when
#    iterating, so every attempt is accepted.
#
# 3. File SIZE must be exactly 489472 bytes (= original stock size).
#    Klipper's ~37KB binary must be padded with 0xFF.
#
# 4. Bootloader offset is 32KiB (0x8000), NOT 28KiB.  Using 0x7000 lets the
#    flash succeed (5 beeps) but the MCU jumps to 0x08008000 which is empty,
#    crashes immediately, and emits nothing on UART.  Config MUST include:
#        CONFIG_STM32_FLASH_START_8000=y
#
# 5. Success signal: LCD shows "Updating..." for ~30s, then 5 beeps.
#    LCD then hangs on splash screen (expected - Klipper doesn't speak
#    the screen's protocol).
#
# 6. Recovery: flash back main_board_20210902_viper_v2.4.5.bin (original).
#    A local copy is kept at $(BACKUP_FIRMWARE) below.

# ----------------------------------------------------------------------------
# BUILD CONFIGURATION (the exact .config that works)
# ----------------------------------------------------------------------------
# CONFIG_LOW_LEVEL_OPTIONS=y
# CONFIG_MACH_STM32=y
# CONFIG_MACH_STM32F103=y
# CONFIG_STM32_CLOCK_REF_8M=y
# CONFIG_STM32_FLASH_START_8000=y            <-- 32KiB bootloader offset
# CONFIG_STM32F103GD_DISABLE_SWD=y           <-- required for GD32 clone
# CONFIG_STM32_SERIAL_USART1=y               <-- PA10/PA9 to CH340
# CONFIG_SERIAL=y
# CONFIG_SERIAL_BAUD=250000
#
# Reference: https://github.com/Klipper3d/klipper/blob/master/config/printer-anycubic-vyper-2021.cfg
#
# COMMON PITFALL: `make olddefconfig` silently resolves to CONFIG_USBSERIAL=y
# if the raw .config uses bad variable names (e.g. CONFIG_SERIAL_PORT=1 is
# NOT a valid key).  The build target below greps the resolved .config and
# aborts if USBSERIAL sneaks in.

# ----------------------------------------------------------------------------
# KLIPPER printer.cfg CHANGES NEEDED
# ----------------------------------------------------------------------------
# - [printer] -> replace  max_accel_to_decel = 3600  with  minimum_cruise_ratio = 0
#   (Klipper >=0.12 removed max_accel_to_decel)
# - Comment out [mcu rpi], [adxl345], [resonance_tester] unless the
#   klipper-mcu (Linux host MCU) systemd service is installed.

# ----------------------------------------------------------------------------
# VARIABLES
# ----------------------------------------------------------------------------
KLIPPER_DIR      ?= $(HOME)/klipper
OUT_DIR          ?= $(HOME)/printer_data/config/firmware
BACKUP_FIRMWARE  ?= $(HOME)/printer_data/sdcard/main_board_20210902_viper_v2.4.5.bin
MOUNT_POINT      ?= /mnt/sdcard
SD_DEVICE        ?= /dev/sda1
TARGET_SIZE      ?= 489472
VERSION          ?= v2.5.1
FLASH_DATE       ?= $(shell date +%Y%m%d)
BIN_NAME         := main_board_$(FLASH_DATE)_viper_$(VERSION).bin
LATEST_LINK      := $(OUT_DIR)/klipper-stm32f103-latest.bin
KCONFIG          := $(OUT_DIR)/vyper-gd32f103.config

# ----------------------------------------------------------------------------
# TARGETS
# ----------------------------------------------------------------------------
.PHONY: help build flash restore verify clean probe check-config

help:
	@echo "Anycubic Vyper / TriGorilla+ V0.0.6 Klipper firmware targets:"
	@echo "  make -f $(lastword $(MAKEFILE_LIST)) build              - compile Klipper bin"
	@echo "  make -f $(lastword $(MAKEFILE_LIST)) flash VERSION=v2.5.2  - pad + copy to SD (SD must be at $(SD_DEVICE))"
	@echo "  make -f $(lastword $(MAKEFILE_LIST)) restore            - copy original firmware back to SD"
	@echo "  make -f $(lastword $(MAKEFILE_LIST)) verify             - probe /dev/ttyUSB0 for Klipper response"
	@echo "  make -f $(lastword $(MAKEFILE_LIST)) probe              - serial diagnostics (multi baud/parity)"
	@echo "  make -f $(lastword $(MAKEFILE_LIST)) check-config       - show current Klipper .config key vars"

$(KCONFIG):
	@mkdir -p $(OUT_DIR)
	@printf '%s\n' \
	  'CONFIG_LOW_LEVEL_OPTIONS=y' \
	  'CONFIG_MACH_STM32=y' \
	  'CONFIG_MACH_STM32F103=y' \
	  'CONFIG_STM32_CLOCK_REF_8M=y' \
	  'CONFIG_STM32_FLASH_START_8000=y' \
	  'CONFIG_STM32F103GD_DISABLE_SWD=y' \
	  'CONFIG_STM32_SERIAL_USART1=y' \
	  'CONFIG_SERIAL=y' \
	  'CONFIG_SERIAL_BAUD=250000' \
	  > $@

build: $(KCONFIG)
	@echo ">>> Cleaning Klipper build tree"
	$(MAKE) -C $(KLIPPER_DIR) clean
	$(MAKE) -C $(KLIPPER_DIR) distclean 2>/dev/null || true
	@echo ">>> Applying Vyper GD32F103 config"
	cp $(KCONFIG) $(KLIPPER_DIR)/.config
	$(MAKE) -C $(KLIPPER_DIR) olddefconfig
	@echo ">>> Sanity-checking resolved .config"
	@if grep -q '^CONFIG_USBSERIAL=y' $(KLIPPER_DIR)/.config; then \
	    echo "FATAL: olddefconfig resolved to USBSERIAL - USART option was rejected."; \
	    grep -E 'USART|USBSERIAL|CONFIG_SERIAL' $(KLIPPER_DIR)/.config; \
	    exit 1; \
	fi
	@grep -E '^CONFIG_STM32_SERIAL_USART|^CONFIG_STM32F103GD|^CONFIG_SERIAL_BAUD|^CONFIG_STM32_FLASH_START|^CONFIG_STM32_CLOCK' $(KLIPPER_DIR)/.config
	@echo ">>> Compiling"
	$(MAKE) -C $(KLIPPER_DIR) -j$$(nproc)
	@mkdir -p $(OUT_DIR)
	cp $(KLIPPER_DIR)/out/klipper.bin $(OUT_DIR)/$(BIN_NAME)
	ln -sf $(BIN_NAME) $(LATEST_LINK)
	@echo ">>> Built: $(OUT_DIR)/$(BIN_NAME)"

flash:
	@[ -f $(LATEST_LINK) ] || { echo "Run 'make build' first"; exit 1; }
	@test -b $(SD_DEVICE) || { echo "$(SD_DEVICE) not present - insert USB SD reader"; exit 1; }
	@echo ">>> Mounting $(SD_DEVICE) at $(MOUNT_POINT)"
	@mountpoint -q $(MOUNT_POINT) || { sudo mkdir -p $(MOUNT_POINT); sudo mount $(SD_DEVICE) $(MOUNT_POINT); }
	@echo ">>> Removing existing main_board_*.bin on SD"
	@sudo find $(MOUNT_POINT) -maxdepth 1 -name 'main_board_*.bin' -print -delete
	@echo ">>> Padding $(LATEST_LINK) to $(TARGET_SIZE) bytes"
	@cp $(LATEST_LINK) /tmp/klipper-padded.bin
	@CUR=$$(stat -c%s /tmp/klipper-padded.bin); PAD=$$(( $(TARGET_SIZE) - CUR )); \
	 head -c $$PAD /dev/zero | tr '\0' '\377' >> /tmp/klipper-padded.bin
	@echo ">>> Copying to SD as $(BIN_NAME)"
	@sudo cp /tmp/klipper-padded.bin $(MOUNT_POINT)/$(BIN_NAME)
	@sudo sync
	@ls -la $(MOUNT_POINT)/
	@sudo umount $(MOUNT_POINT)
	@echo ">>> Done. Insert SD into Vyper, power-cycle, wait ~30s."
	@echo ">>> Expect:  'Updating...' then 5 beeps, then splash-stuck screen."

restore:
	@[ -f $(BACKUP_FIRMWARE) ] || { echo "Backup not found: $(BACKUP_FIRMWARE)"; exit 1; }
	@test -b $(SD_DEVICE) || { echo "$(SD_DEVICE) not present"; exit 1; }
	@sudo mkdir -p $(MOUNT_POINT)
	@mountpoint -q $(MOUNT_POINT) || sudo mount $(SD_DEVICE) $(MOUNT_POINT)
	@sudo find $(MOUNT_POINT) -maxdepth 1 -name 'main_board_*.bin' -print -delete
	@RESTORE_NAME=main_board_$(FLASH_DATE)_viper_v2.4.5.bin; \
	 sudo cp $(BACKUP_FIRMWARE) $(MOUNT_POINT)/$$RESTORE_NAME; \
	 sudo sync; \
	 ls -la $(MOUNT_POINT)/
	@sudo umount $(MOUNT_POINT)
	@echo ">>> Original firmware restored to SD. Power-cycle Vyper to flash back."

verify:
	@echo ">>> Klipper printer info:"
	@curl -s http://localhost:7125/printer/info | python3 -c "import json,sys; d=json.load(sys.stdin)['result']; print('state:', d['state']); print('msg:', d['state_message'][:300])"
	@echo ">>> Recent klippy.log:"
	@tail -n 10 $(HOME)/printer_data/logs/klippy.log

probe:
	@echo ">>> Stopping klipper to free /dev/ttyUSB0"
	-@curl -s -X POST "http://localhost:7125/machine/services/stop?service=klipper" >/dev/null
	@sleep 2
	@python3 -c "\
import serial,time;\
s=serial.Serial('/dev/ttyUSB0',250000,timeout=1.5);\
s.dtr=False; s.rts=True; time.sleep(0.1);\
s.dtr=True;  s.rts=False; time.sleep(0.3);\
s.reset_input_buffer();\
[s.write(b'\x01\x01\x01\x7e') or time.sleep(0.2) for _ in range(4)];\
buf=s.read(200);\
print(f'baud=250000 8N1: {len(buf)} bytes: {buf[:48].hex()}');\
print('OK - saw 0x7e sync' if b'\x7e' in buf else 'WARN - no sync byte seen')"
	-@curl -s -X POST "http://localhost:7125/machine/services/start?service=klipper" >/dev/null

check-config:
	@grep -E '^CONFIG_STM32_SERIAL_USART|^CONFIG_STM32F103GD|^CONFIG_USBSERIAL|^CONFIG_SERIAL_BAUD|^CONFIG_STM32_FLASH_START|^CONFIG_STM32_CLOCK_REF' $(KLIPPER_DIR)/.config || true

clean:
	rm -f $(OUT_DIR)/main_board_*.bin $(LATEST_LINK) $(KCONFIG) /tmp/klipper-padded.bin

# ----------------------------------------------------------------------------
# END-TO-END FLASH PROCEDURE (manual steps)
# ----------------------------------------------------------------------------
# 1. Insert SD card into USB reader on the Pi (NOT in the printer).
# 2. make -f anycubic-VyperCE61b-klipper-firmware.mk build VERSION=v2.5.2
# 3. make -f anycubic-VyperCE61b-klipper-firmware.mk flash VERSION=v2.5.2
# 4. Eject SD from Pi, insert into Vyper's SD slot.
# 5. Power-cycle Vyper.  Wait ~30s.  Listen for 5 beeps.
# 6. make -f anycubic-VyperCE61b-klipper-firmware.mk verify
#    -> expect "state: ready".
#
# If "state: error (mcu 'mcu': Unable to connect)":
#   - make probe                  # check UART for Klipper sync bytes
#   - Bump VERSION (e.g. v2.5.3) and FLASH_DATE to 20261231, reflash.
#   - If still broken: make restore to go back to stock Marlin.
# ============================================================================
