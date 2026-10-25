#!/usr/bin/env bash
# Flash Mobile NixOS over pmOS. Phone in fastboot mode (adb reboot bootloader,
# or power + volume down).
#   ./flash.sh [images-dir]        default: build/images (./build.sh images)
# SLOT picks the slot for boot/dtbo (default b). On this phone pmOS, and now
# NixOS, live on slot a: SLOT=a ./flash.sh images
# The rootfs goes to userdata, which is shared by both slots: this erases pmOS.
set -euo pipefail
cd "$(dirname "$0")"

IMG=${1:-build/images}
SLOT=${SLOT:-b}
FASTBOOT=${FASTBOOT:-fastboot}

[ -f "$IMG/boot.img" ] && [ -f "$IMG/system.img" ] || {
	echo "no boot.img/system.img in $IMG; run: ./build.sh images" >&2
	exit 1
}

product=$($FASTBOOT getvar product 2>&1 | awk '/^product:/{print $2}')
current=$($FASTBOOT getvar current-slot 2>&1 | awk '/^current-slot:/{print $2}')
echo "device: $product, current slot: $current, flashing slot: $SLOT"
[ "$product" = dubai ] || { echo "not a dubai ($product), refusing" >&2; exit 1; }

read -rp "This overwrites boot_$SLOT, dtbo_$SLOT and userdata (pmOS). Continue? [y/N] " ok
[ "$ok" = y ] || exit 1

# ABL can't apply the stock dtbo to the mainline dtb (pmOS ships an empty one)
dtbo=$(mktemp)
trap 'rm -f $dtbo' EXIT
dd if=/dev/zero of="$dtbo" bs=25165824 count=1 status=none

set -x
$FASTBOOT flash "dtbo_$SLOT" "$dtbo"
$FASTBOOT flash "boot_$SLOT" "$IMG/boot.img"
$FASTBOOT flash userdata "$IMG/system.img"
$FASTBOOT --set-active="$SLOT"
$FASTBOOT reboot
