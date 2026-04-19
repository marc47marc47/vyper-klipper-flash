#!/usr/bin/env bash
# Restore Vyper's original Anycubic firmware from local backup.
set -euo pipefail

BACKUP="$HOME/printer_data/sdcard/main_board_20210902_viper_v2.4.5.bin"
MOUNT_POINT="/mnt/sdcard"

[[ -f "$BACKUP" ]] || { echo "ERROR: backup not found: $BACKUP"; exit 1; }

if ! mountpoint -q "$MOUNT_POINT"; then
    echo ">>> Mounting /dev/sda1..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount /dev/sda1 "$MOUNT_POINT"
fi

echo ">>> Clearing existing main_board_*.bin on SD..."
sudo find "$MOUNT_POINT" -maxdepth 1 -name 'main_board_*.bin' -print -delete

# Use a NEWER date than original so the bootloader treats it as an upgrade.
DATE="$(date +%Y%m%d)"
TARGET="$MOUNT_POINT/main_board_${DATE}_viper_v2.4.5.bin"
echo ">>> Copying original firmware to SD as: $(basename "$TARGET")"
sudo cp "$BACKUP" "$TARGET"
sudo sync

ls -la "$MOUNT_POINT" | sed 's/^/    /'
sudo umount "$MOUNT_POINT"
echo
echo ">>> Done. Insert SD into Vyper, power-cycle, wait 60 seconds."
echo "    Expected: normal boot into Anycubic UI menu."
