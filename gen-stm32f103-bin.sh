#!/usr/bin/env bash
# Build Klipper MCU firmware for Anycubic Vyper / TriGorilla+ V0.0.6
#   MCU: GD32F103RET6 (GigaDevice clone, treated as STM32F103)
#   Bootloader: 28KiB, serial flash via SD card
# Usage: ./gen-stm32f103-bin.sh [VERSION] [USART]
#   VERSION : filename version tag  (default: v9.9.9)
#   USART   : 1 | 2 | 3             (default: 1 -> PA10/PA9 to CH340)
set -euo pipefail

VERSION="${1:-v9.9.9}"
USART="${2:-1}"
KLIPPER_DIR="${KLIPPER_DIR:-$HOME/klipper}"
OUT_DIR="${OUT_DIR:-$HOME/printer_data/config/firmware}"
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/stm32f103-vyper.config"

case "$USART" in
    1) SERIAL_OPT="CONFIG_STM32_SERIAL_USART1=y" ;;
    2) SERIAL_OPT="CONFIG_STM32_SERIAL_USART2=y" ;;
    3) SERIAL_OPT="CONFIG_STM32_SERIAL_USART3=y" ;;
    *) echo "USART must be 1, 2, or 3"; exit 1 ;;
esac

cat > "$CONFIG_FILE" <<EOF
# Klipper MCU config - Anycubic TriGorilla+ V0.0.6 (GD32F103RET6)
CONFIG_LOW_LEVEL_OPTIONS=y
CONFIG_MACH_STM32=y
CONFIG_MACH_STM32F103=y
CONFIG_STM32_CLOCK_REF_8M=y
CONFIG_STM32_FLASH_START_8000=y
CONFIG_STM32F103GD_DISABLE_SWD=y
$SERIAL_OPT
CONFIG_SERIAL=y
CONFIG_SERIAL_BAUD=250000
EOF

cd "$KLIPPER_DIR"
echo ">>> Cleaning previous build..."
make clean
make distclean 2>/dev/null || true

echo ">>> Using config (USART$USART, GD32F103):"
grep -E "USART|USBSERIAL|DISABLE_SWD|CLOCK_REF" "$CONFIG_FILE" || true
cp "$CONFIG_FILE" .config
make olddefconfig

echo ">>> Verifying resolved .config:"
if grep -q "^CONFIG_USBSERIAL=y" .config; then
    echo "ERROR: config resolved to USBSERIAL - USART option rejected."
    grep -E "USART|USBSERIAL|CONFIG_SERIAL" .config
    exit 1
fi
grep -E "^CONFIG_STM32_SERIAL_USART|^CONFIG_STM32F103GD|^CONFIG_SERIAL_BAUD|^CONFIG_STM32_CLOCK" .config

echo ">>> Compiling..."
make -j"$(nproc)"

mkdir -p "$OUT_DIR"
DATE="$(date +%Y%m%d)"
VYPER_NAME="main_board_${DATE}_viper_${VERSION}.bin"
OUT_BIN="$OUT_DIR/${VYPER_NAME}"
cp out/klipper.bin "$OUT_BIN"
ln -sf "$VYPER_NAME" "$OUT_DIR/klipper-stm32f103-latest.bin"

echo
echo ">>> Build successful"
echo "    Output : $OUT_BIN"
echo "    Symlink: $OUT_DIR/klipper-stm32f103-latest.bin"
echo "    USART  : $USART ; GD32F103GD_DISABLE_SWD=y"
