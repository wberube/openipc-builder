#!/usr/bin/env python3
"""Compose an 8 MB NOR image for the Meari Mini 7C (Anyka AK3918EV200).

The image uses OpenIPC's AK3918EV200 U-Boot and the layout both that
U-Boot and the EV200 DTS use:

    0x000000  256 KiB  u-boot-ak3918ev200-nor.bin
    0x040000   64 KiB  U-Boot environment
    0x050000    2 MiB  uImage.ak3918ev200
    0x250000    5 MiB  rootfs.squashfs.ak3918ev200
    0x750000  704 KiB  rootfs_data (left erased)

The U-Boot environment is seeded from the defaults compiled into the
official U-Boot binary, so fw_setenv works on the first boot. If a stock
read-out is given, its ethaddr is carried over; the read-out is a local file,
not part of this repository.

    ./make-image.py --uboot u-boot-ak3918ev200-nor.bin \
                    --kernel uImage.ak3918ev200 \
                    --rootfs rootfs.squashfs.ak3918ev200 \
                    --stock /path/to/stock-dump.bin

U-Boot is published as
https://github.com/OpenIPC/firmware/releases/download/latest/u-boot-ak3918ev200-nor.bin
"""

import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

FLASH_SIZE = 0x800000
UBOOT_OFF = 0x000000
UBOOT_MAX = 0x040000
ENV_OFF = 0x040000
ENV_SIZE = 0x10000
KERN_OFF = 0x050000
KERN_MAX = 0x200000
ROOT_OFF = 0x250000
ROOT_MAX = 0x500000


def die(msg):
    raise SystemExit(msg)


def env_defaults(uboot):
    marker = b"bootcmd=run bootflash\x00"
    start = uboot.find(marker)
    if start < 0:
        die("this U-Boot has no AK3918EV200 default environment")
    entries = []
    pos = start
    while pos < len(uboot):
        end = uboot.find(b"\x00", pos)
        if end < 0 or end == pos:
            break
        entry = uboot[pos:end].decode("ascii", "replace")
        if "=" in entry:
            entries.append(entry)
        pos = end + 1
    if len(entries) < 20:
        die("short default environment in this U-Boot")
    return entries


def set_key(entries, key, value):
    for i, entry in enumerate(entries):
        if entry.split("=", 1)[0] == key:
            entries[i] = "%s=%s" % (key, value)
            return
    entries.append("%s=%s" % (key, value))


def stock_mac(dump):
    # Prefer the saved environment at 0x40000 over the copy embedded in
    # the U-Boot binary at the start of the part.
    for lo, hi in ((0x40000, 0x42000), (0, 0x70000)):
        m = re.search(rb"ethaddr=([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})",
                      dump[lo:hi])
        if m:
            return m.group(1).decode("ascii").lower()
    return None


def build_env(entries):
    data = b"\x00".join(entry.encode("ascii") for entry in entries) + b"\x00"
    if len(data) > ENV_SIZE - 4:
        die("environment is too large: %d bytes" % len(data))
    data = data.ljust(ENV_SIZE - 4, b"\x00")
    return struct.pack("<I", zlib.crc32(data) & 0xffffffff) + data


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--uboot", required=True, type=Path,
                    help="u-boot-ak3918ev200-nor.bin")
    ap.add_argument("--kernel", required=True, type=Path,
                    help="uImage.ak3918ev200")
    ap.add_argument("--rootfs", required=True, type=Path,
                    help="rootfs.squashfs.ak3918ev200")
    ap.add_argument("--stock", type=Path,
                    help="optional local stock read-out, to keep its ethaddr")
    ap.add_argument("--out", type=Path,
                    default=Path("ak3918ev200_lite_meari-mini-7c-nor.bin"))
    ap.add_argument("--upgrade",
                    default="https://github.com/OpenIPC/builder/releases/download/latest/ak3918ev200_lite_meari-mini-7c-nor.tgz",
                    help="upgrade URL written into the environment")
    ap.add_argument("--wlandev", default="8188fu",
                    help="wlandev written into the environment")
    args = ap.parse_args()

    uboot = args.uboot.read_bytes()
    kernel = args.kernel.read_bytes()
    rootfs = args.rootfs.read_bytes()

    if len(uboot) > UBOOT_MAX:
        die("U-Boot is %d bytes, over the %d-byte boot partition"
            % (len(uboot), UBOOT_MAX))
    if len(kernel) > KERN_MAX:
        die("kernel is %d bytes, over the %d-byte kernel partition"
            % (len(kernel), KERN_MAX))
    if len(rootfs) > ROOT_MAX:
        die("rootfs is %d bytes, over the %d-byte rootfs partition"
            % (len(rootfs), ROOT_MAX))
    if kernel[:4] != b"\x27\x05\x19\x56":
        die("%s is not a uImage" % args.kernel)
    if rootfs[:4] not in (b"hsqs", b"sqsh"):
        die("%s is not a squashfs image" % args.rootfs)

    entries = env_defaults(uboot)
    if args.stock:
        mac = stock_mac(args.stock.read_bytes())
        if mac:
            set_key(entries, "ethaddr", mac)
            print("preserving ethaddr %s from %s" % (mac, args.stock))
        else:
            print("no ethaddr found in %s, leaving the default" % args.stock)
    set_key(entries, "wlandev", args.wlandev)
    set_key(entries, "upgrade", args.upgrade)
    env = build_env(entries)

    image = bytearray(b"\xff" * FLASH_SIZE)
    image[UBOOT_OFF:UBOOT_OFF + len(uboot)] = uboot
    image[ENV_OFF:ENV_OFF + ENV_SIZE] = env
    image[KERN_OFF:KERN_OFF + len(kernel)] = kernel
    image[ROOT_OFF:ROOT_OFF + len(rootfs)] = rootfs
    args.out.write_bytes(image)

    print("u-boot  %8d bytes  @ 0x%06x" % (len(uboot), UBOOT_OFF))
    print("env     %8d bytes  @ 0x%06x" % (ENV_SIZE, ENV_OFF))
    print("kernel  %8d bytes  @ 0x%06x" % (len(kernel), KERN_OFF))
    print("rootfs  %8d bytes  @ 0x%06x" % (len(rootfs), ROOT_OFF))
    print("wrote %s (%d bytes)" % (args.out, len(image)))


if __name__ == "__main__":
    main()
