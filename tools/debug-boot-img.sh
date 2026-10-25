#!/usr/bin/env bash
# Debug boot.img: the system's stage-1 initrd with a busybox init in front.
# It brings up USB NCM (phone 172.16.42.1) + telnet :23, waits for /debug/go
# (or 90 s), then runs NixOS' stage-1 (/init.nixos) as a *child*, so the shell
# survives a stage-1 failure and /.error.json can be read.
# Use with `fastboot boot` only. See docs/troubleshooting.md.
#
#   ./build.sh kernel system          # inputs: build/kernel, build/system
#   tools/debug-boot-img.sh [out.img] # default: build/boot-debug.img
#
# On the PC the NCM link shows up as a new interface; give it an address:
#   nmcli device modify <iface> ipv4.method manual ipv4.addresses 172.16.42.2/24
#   nc 172.16.42.1 23
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT=$(realpath -m "${1:-$SRC/build/boot-debug.img}")
PANEL=${PANEL:-csot}

K=$(readlink -f "$SRC/build/kernel")
INITRD=$(readlink -f "$SRC/build/system/initrd")
# linuxManualConfig puts modules in a separate output; the old builder didn't
M=$(nix-store -q --outputs "$(nix-store -q --deriver "$K")" | grep -- '-modules$' || echo "$K")
V=$(ls "$M/lib/modules")
DTB=$K/dtbs/qcom/sm7325-motorola-dubai-$PANEL.dtb

pkgs="let p = import $SRC/userspace/mobile-nixos/pkgs.nix { overlays = [ (import $SRC/userspace/mobile-nixos/overlay/overlay.nix) ]; }; in"
tool() { nix-build --no-out-link -E "$pkgs p.$1" 2>/dev/null; }
BUSYBOX=$(tool pkgsCross.aarch64-multiplatform.pkgsStatic.busybox)/bin/busybox
PATH=$(tool mkbootimg)/bin:$(tool zstd)/bin:$(tool cpio)/bin:$(tool python3)/bin:$PATH

W=$(mktemp -d); trap 'chmod -R u+w "$W"; rm -rf "$W"' EXIT
R=$W/root
mkdir -p "$R"
( cd "$R" && zstd -dc "$INITRD" | cpio -id --quiet )
chmod -R u+w "$R"
mv "$R/init" "$R/init.nixos"
mkdir -p "$R/debug/bin" "$R/debug/modules"
cp "$BUSYBOX" "$R/debug/busybox"
for m in libcomposite u_ether usb_f_ncm u_serial usb_f_acm; do
  f=$(find "$M/lib/modules/$V" -name "$m.ko*" | head -1)
  [ -n "$f" ] || { echo "module $m not found" >&2; exit 1; }
  case $f in
    *.zst) zstd -dq "$f" -o "$R/debug/modules/$m.ko" ;;
    *) cp "$f" "$R/debug/modules/$m.ko" ;;
  esac
done
printf '#!/debug/busybox sh\nexport PATH=/debug/bin\nexec /debug/busybox sh -l\n' > "$R/debug/sh"
cat > "$R/init" <<'INIT'
#!/debug/busybox sh
B=/debug/busybox
$B --install -s /debug/bin
export PATH=/debug/bin
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts; mount -t devpts devpts /dev/pts
mount -t configfs configfs /sys/kernel/config
for m in libcomposite u_ether usb_f_ncm u_serial usb_f_acm; do insmod /debug/modules/$m.ko; done
for r in /sys/class/usb_role/*/role; do echo device > "$r"; done
G=/sys/kernel/config/usb_gadget/dbg
mkdir -p $G/strings/0x409 $G/configs/c.1/strings/0x409 $G/functions/acm.gs0 $G/functions/ncm.usb0
echo 0x1d6b > $G/idVendor; echo 0x0110 > $G/idProduct
echo "Motorola Edge 30 (debug)" > $G/strings/0x409/product
echo debug > $G/configs/c.1/strings/0x409/configuration
ln -s $G/functions/acm.gs0 $G/configs/c.1/; ln -s $G/functions/ncm.usb0 $G/configs/c.1/
i=0; while [ $i -lt 30 ] && [ -z "$(ls /sys/class/udc)" ]; do i=$((i+1)); sleep 1; done
ls /sys/class/udc | head -n1 > $G/UDC
sleep 1
# Not usb0: stage-1's DHCPD task would fire before PATH is set ("Command not found")
ip link set usb0 name dbg0
ifconfig dbg0 172.16.42.1 netmask 255.255.255.0 up
telnetd -l /debug/sh -p 23
echo "== debug-init: telnet up; touch /debug/go to start /init.nixos" > /dev/kmsg
i=0; while [ $i -lt 90 ] && [ ! -e /debug/go ]; do i=$((i+1)); sleep 1; done
echo "== debug-init: starting /init.nixos $*" > /dev/kmsg
env -i HOME=/ TERM=linux /init.nixos "$@" <&- >&- 2>&-
echo "== /init.nixos exited: $?" > /dev/kmsg
while true; do sleep 3600; done
INIT
chmod 755 "$R/init" "$R/debug/sh" "$R/debug/busybox"

( cd "$R" && find . | cpio -o -H newc --owner=root:root --quiet | zstd -19 -q ) > "$W/initrd.zst"
cat "$K/Image.gz" "$DTB" > "$W/kernel"
# Offsets as in userspace/devices/motorola-dubai/default.nix (pmOS deviceinfo_flash_*)
mkbootimg --header_version 2 \
  --kernel "$W/kernel" --ramdisk "$W/initrd.zst" --dtb "$DTB" \
  --base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
  --tags_offset 0x100 --dtb_offset 0x1f00000 --pagesize 4096 \
  --os_patch_level 2026-06-26 \
  --cmdline 'console=tty2 earlycon loglevel=7' \
  -o "$OUT"

python3 - "$OUT" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read(4096)
ks, ka, rs, ra = struct.unpack_from("<4I", b, 8)
print("ramdisk ends", hex(ra + rs), "OK" if ra + rs < 0x1f00000 else "OVERLAP")
if ra + rs >= 0x1f00000:
    sys.exit(1)
PY
echo "$OUT"
