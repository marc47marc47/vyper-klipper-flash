#!/usr/bin/env bash
# Pad Klipper bin to ~500KB (Vyper bootloader rejects too-small files)
# and copy as the ONLY main_board_*.bin on the SD card.
# Uses a clean version format (vX.Y.Z) because Vyper bootloader may
# reject names with extra suffixes like "-klipper".
set -euo pipefail

VERSION="${1:-v9.9.9}"
MOUNT_POINT="/mnt/sdcard"
SRC_BIN="$HOME/printer_data/config/firmware/klipper-stm32f103-latest.bin"
PAD_SIZE="${PAD_SIZE:-491520}"  # 480 KB

[[ -f "$SRC_BIN" ]] || { echo "ERROR: $SRC_BIN not found"; exit 1; }

if ! mountpoint -q "$MOUNT_POINT"; then
    echo ">>> SD card not mounted; attempting /dev/sda1..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount /dev/sda1 "$MOUNT_POINT"
fi

DATE="$(date +%Y%m%d)"
TARGET_NAME="main_board_${DATE}_viper_${VERSION}.bin"
TARGET_PATH="$MOUNT_POINT/$TARGET_NAME"
PADDED_TMP="/tmp/klipper-padded.bin"

echo ">>> Removing existing main_board_*.bin from SD card (keeping .orig)..."
sudo find "$MOUNT_POINT" -maxdepth 1 -name 'main_board_*.bin' -not -name '*.orig' -print -delete || true

echo ">>> Padding Klipper bin to $PAD_SIZE bytes with 0xFF..."
cp "$SRC_BIN" "$PADDED_TMP"
SRC_SIZE=$(stat -c%s "$PADDED_TMP")
PAD_BYTES=$((PAD_SIZE - SRC_SIZE))
if (( PAD_BYTES > 0 )); then
    head -c "$PAD_BYTES" /dev/zero | tr '\0' '\377' >> "$PADDED_TMP"
fi
echo "    padded size: $(stat -c%s "$PADDED_TMP") bytes"

echo ">>> Copying to SD card as: $TARGET_NAME"
sudo cp "$PADDED_TMP" "$TARGET_PATH"
sudo sync

echo
echo ">>> SD card contents:"
ls -la "$MOUNT_POINT" | sed 's/^/    /'
echo
echo ">>> Unmounting..."
sudo umount "$MOUNT_POINT"
echo ">>> Done. Insert SD into Vyper, power-cycle, wait 60 seconds."
