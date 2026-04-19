#!/usr/bin/env bash
# Copy Klipper firmware bin to an inserted USB SD-card reader for Anycubic Vyper.
# Usage: ./copy-to-sdcard.sh [VERSION] [DEVICE]
#   VERSION : version tag appended to filename (default: v3.0.0-klipper)
#             Must differ from any previously flashed filename, or the Vyper
#             bootloader will skip re-flashing.
#   DEVICE  : block device to use (default: auto-detect first USB removable)
#
# Examples:
#   ./copy-to-sdcard.sh
#   ./copy-to-sdcard.sh v3.0.1-klipper
#   ./copy-to-sdcard.sh v3.0.1-klipper /dev/sda1
set -euo pipefail

VERSION="${1:-v3.0.0-klipper}"
DEVICE="${2:-}"
FIRMWARE_DIR="${FIRMWARE_DIR:-$HOME/printer_data/config/firmware}"
SRC_BIN="${SRC_BIN:-$FIRMWARE_DIR/klipper-stm32f103-latest.bin}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/sdcard}"

if [[ ! -f "$SRC_BIN" ]]; then
    echo "ERROR: firmware not found at $SRC_BIN"
    echo "       Run gen-stm32f103-bin.sh first."

    exit 1
fi

if [[ -z "$DEVICE" ]]; then
  echo "ERROR: no USB removable partition found. Plug in the SD reader."
  echo "
  功能：
  - 自動偵測 USB 可移除式儲存裝置（免手動指定 /dev/sda1）
  - 自動掛載 到 /mnt/sdcard
  - 檢查目標檔名是否已存在（避免 bootloader 略過燒錄）
  - 複製並顯示前後目錄內容
  - 自動 sync + umount（透過 trap，中途失敗也會清乾淨）

  使用方式：
  # 預設版本
  ./copy-to-sdcard.sh

  # 指定新版本（每次重燒務必換號）
  ./copy-to-sdcard.sh v3.0.1-klipper

  # 指定裝置（若自動偵測錯誤）
  ./copy-to-sdcard.sh v3.0.1-klipper /dev/sda1

  完整燒錄流程（以後只要兩步驟）：
  ./gen-stm32f103-bin.sh v3.0.1     # 編譯
  ./copy-to-sdcard.sh v3.0.1-klipper # 複製到 SD
  # → 拔 USB → SD 卡插印表機 → 關機開機
  "

    DEVICE="$(lsblk -rpno NAME,TRAN,RM,TYPE | awk '$2=="usb" && $3=="1" && $4=="part" {print $1; exit}')"
    if [[ -z "$DEVICE" ]]; then
        echo "Current block devices:"
        lsblk -o NAME,SIZE,FSTYPE,TRAN,RM,MOUNTPOINT
        exit 1
    fi
    echo ">>> Auto-detected USB device: $DEVICE"
fi

cleanup() {
    if mountpoint -q "$MOUNT_POINT"; then
        echo ">>> Syncing and unmounting $MOUNT_POINT..."
        sudo -n sync
        sudo -n umount "$MOUNT_POINT" && echo ">>> Unmounted. You may remove the SD card."
    fi
}
trap cleanup EXIT

sudo -n mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
    echo ">>> $MOUNT_POINT already mounted, reusing."
else
    echo ">>> Mounting $DEVICE at $MOUNT_POINT..."
    sudo -n mount "$DEVICE" "$MOUNT_POINT"
fi

echo ">>> Contents before:"
ls -la "$MOUNT_POINT" | sed 's/^/    /'

DATE="$(date +%Y%m%d)"
TARGET_NAME="main_board_${DATE}_viper_${VERSION}.bin"
TARGET_PATH="$MOUNT_POINT/$TARGET_NAME"

if [[ -e "$TARGET_PATH" ]]; then
    echo "ERROR: $TARGET_NAME already exists on the SD card."
    echo "       Bump the VERSION argument, e.g.:"
    echo "         $0 ${VERSION%%-klipper}-r2-klipper"
    exit 1
fi

echo ">>> Copying firmware..."
echo "    src: $SRC_BIN"
echo "    dst: $TARGET_PATH"
sudo -n cp "$SRC_BIN" "$TARGET_PATH"

echo ">>> Contents after:"
ls -la "$MOUNT_POINT" | sed 's/^/    /'

echo
echo ">>> Done. Next steps:"
echo "    1. Wait for the unmount line below, then remove the USB reader."
echo "    2. Put the SD card into the Vyper's card slot."
echo "    3. Power-cycle the printer; wait ~30 seconds for flashing."
echo "    4. In Mainsail/Fluidd, run: FIRMWARE_RESTART"
