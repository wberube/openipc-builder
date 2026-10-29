# ak3918ev200_lite_meari-mini-7c — bring-up notes

Meari Mini 7C, a Meari/Tuya 720p camera also sold as the Merkury Smart 720p
(vendor PCB `MINI7C_AK_V10`): Anyka AK3918EV200 (ARM926EJ-S, 64 MiB
DDR2), 8 MB XM25QH64A NOR, SuperPix SC1245 (1280x720, DVP), and an
RTL8188FTV USB Wi-Fi (0bda:f179). No PTZ motor; IR-cut and two status
LEDs only.

## Stock dump

A read-out of the stock flash (kept locally, not part of this repository) is
the PPS/Tuya stack: U-Boot at 0, its environment at
0x40000, a Linux 3.4.35 uImage at 0x70000, a cramfs `ppsapp` at
0x2e0000, and a jffs2 config partition around 0x760000. This is a
board-file kernel (no device tree); the GPIO map comes from
`Strnio.ko`'s `ak_mini7c_rev10` PCB table: `redLed` 23, `blueLed` 24,
`irRed` 47, `irCut_1` 14, `irCut_2` 13, `AcShdn` 15, `Restbutton` 11,
`wlanPwr` 20. The vendor image also ships an unused `ssv6x5x.ko`; the
radio on this board is the RTL8188FTV.

## Profile

Targets the current OpenIPC Anyka EV200 port: Linux 4.4.302,
`ak3918ev200.generic.config`, and the official
`u-boot-ak3918ev200-nor.bin`. U-Boot and the DTS agree on:

    0x000000  256K  boot
    0x040000   64K  env
    0x050000    2M  kernel
    0x250000    5M  rootfs
    0x750000  rest  rootfs_data

The EV200 defconfig already builds the SC1245 driver and the camera, ISP
and H.264 encoder drivers, so no osdrv is needed. The Mini 7C deltas are:

- The DTS patch moves the sensor i2c client from the demo board's GC1084
  address 0x37 to SC1245's 0x30 (8-bit 0x60) and sets its 24 MHz MCLK.
  The sensor subdev otherwise auto-detects from the built-in registry.
- Wi-Fi is the Realtek `rtl8188fu` driver, which binds the RTL8188FTV
  (0bda:f179). wpa_supplicant uses `-D wext`, the driver's native path.
  The vendor's `ssv615x` SMAC module is not used.
- The RTL8188EU/MT7601U drivers and the RDA5995 module are dropped; the
  rtl8188fu module is kept. The excludes list strips those plus the CEC
  tools and modem serial stack: the generic EV200 rootfs is 4.93 MB of
  the 5 MB partition.
- The vendor `ak_mini7c_rev10` table puts `wlanPwr` on GPIO 20 (0x14);
  the demo DTS used 34. The DTS patch moves `wifi_en` to 20, wires the
  Mini 7C pins through `user-gpio` (red 23, blue 24, IR 47, IR-cut
  14/13, amp shutdown 15) and ties the reset button (11) to `gpiokeys`.
  The wlandev handler power-cycles GPIO 20 and waits for `wlan0`.

## Build and flash

The EV200 target is in current firmware master. `builder.sh` deletes and
re-clones `openipc/` on every run, so just build:

    ./builder.sh ak3918ev200_lite_meari-mini-7c

The `u-boot-ak3918ev200-nor.bin` in the current `latest` release predates
the `ak_sflash` RX/TRANSF fix (commit 6675d23 on `anyka/spi-rx-transf`).
Its long `sf read`s shift at the first 8 KiB boundary, so the kernel data
CRC fails even though the flash content is correct. Build that branch:

    git clone --depth 1 -b anyka/spi-rx-transf https://github.com/OpenIPC/u-boot
    cd u-boot
    PATH=$BUILDER/openipc/output/host/bin:$PATH \
    CROSS_COMPILE=$BUILDER/openipc/output/host/opt/ext-toolchain/bin/arm-openipc-linux-musleabi- \
        ./build.sh ak3918ev200

The result is `output/u-boot-ak3918ev200-nor.bin` (236 KB, fits the 256 KB
boot partition). Replace the release binary once the fix is merged.

Then compose a whole-chip image. The stock read-out is a local file, not part
of this repository; make-image.py only reads it for its ethaddr and never
modifies it.

    devices/ak3918ev200_lite_meari-mini-7c/flash/make-image.py \
        --uboot u-boot/output/u-boot-ak3918ev200-nor.bin \
        --kernel openipc/output/images/uImage.ak3918ev200 \
        --rootfs openipc/output/images/rootfs.squashfs.ak3918ev200 \
        --stock /path/to/stock-dump.bin

Flash the result at 0x0 with the CH341A. This replaces the vendor
bootloader; without that read-out there is no way back to the PPS firmware.

## Status

Built and flashed. The fixed U-Boot from `anyka/spi-rx-transf` is
required: with it the kernel CRC passes, SC1245 is detected and the
rootfs mounts. The first image left the USB WiFi unpowered because the
demo DTS used GPIO 34; the Mini 7C table puts `wlanPwr` on GPIO 20.
The module now enumerates; the profile builds the `rtl8188fu` driver for
the RTL8188FTV. Video is still not wired (the EV200 image has no
streamer); the IR-cut, LEDs, reset button and amp shutdown are wired as
`user-gpio`/`gpiokeys` for testing.

Background: OpenIPC's AK3918EV200 research tree, especially
`docs/OpenIPC_AK3918_programming.md` and `docs/sdk/ak3918_sdk_notes.md`.
