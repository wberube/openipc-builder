#!/bin/sh
#
# Compose a flashable 16 MB NOR image for the BeeWi BC7PW (GM8135S).
#
#   ./make-image.sh [uImage.gm8135s] [rootfs.squashfs.gm8135s] [out.bin]
#
# The boot region -- first-stage loader, U-Boot and its environment, the first
# 0x60000 of the part -- cannot be built by OpenIPC; it comes from a read-out of
# a working camera and is kept here as bootloader.bin (set BOOT= to use another
# read-out). The kernel and the rootfs are the build's output
# (openipc/output/images/). The result is written to be flashed at offset 0.
#
set -eu

here=$(cd "$(dirname "$0")" && pwd)
boot=${BOOT:-$here/bootloader.bin}

uimage=${1:-uImage.gm8135s}
rootfs=${2:-rootfs.squashfs.gm8135s}
out=${3:-gm8135s_lite_beewi-bc7pw-nor.bin}

kern_off=$((0x060000))
root_off=$((0x260000))
flash_size=$((0x1000000))

for f in "$boot" "$uimage" "$rootfs"; do
	[ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done

[ "$(wc -c < "$uimage")" -le $((root_off - kern_off)) ] \
	|| { echo "$uimage does not fit below 0x260000" >&2; exit 1; }
[ "$(wc -c < "$rootfs")" -le $((flash_size - root_off)) ] \
	|| { echo "$rootfs does not fit above 0x260000" >&2; exit 1; }

# 0xFF fill, not 0x00: an erased NOR cell reads 0xFF, and jffs2 refuses a
# zeroed partition ("Magic bitmask 0x1985 not found"), which costs a format of
# the data partition on the first boot.
dd if=/dev/zero bs=1M count=16 2>/dev/null | tr '\000' '\377' > "$out"
dd if="$boot"   of="$out" bs=1K count=384 conv=notrunc 2>/dev/null
dd if="$uimage" of="$out" bs=1K seek=$((kern_off / 1024)) conv=notrunc 2>/dev/null
dd if="$rootfs" of="$out" bs=1K seek=$((root_off / 1024)) conv=notrunc 2>/dev/null

echo "$out: $(wc -c < "$out") bytes"
