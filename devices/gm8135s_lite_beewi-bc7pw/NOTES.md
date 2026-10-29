# gm8135s_lite_beewi-bc7pw — bring-up notes

BeeWi BC7PW, also sold as Wansview NCM703GC. GrainMedia GM8135S
(arm926ej-s), 16 MB NOR, MT7601 USB Wi-Fi, OV9732 sensor. Build with
`make BOARD=gm8135s_lite_beewi-bc7pw`.

No serial header on this board and no soldering iron on hand, so everything has
been diagnosed from the build and from what reaches the console. The profile
ships no debug scaffolding; that comes out of the local archive if someone needs
it again.

## Profile

    general/overlay/init                                (data partition + read-write union)
    general/overlay/etc/fw_env.config
    general/overlay/etc/wireless/usb
    general/overlay/etc/network/interfaces.d/wlan0      (WEXT stanza)
    general/overlay/etc/init.d/S40network               (eth0 carrier gating)
    general/overlay/usr/share/openipc/customizer.sh
    general/scripts/excludes/gm8135s_lite.list
    general/package/all-patches/mt7601u-openipc/*.patch

Defconfig: SOC_MODEL=gm8135s, 16 MB flash, MT7601U_OPENIPC instead of
RTL8188EU, and WEXT built into wpa_supplicant — this vendor mt7601sta driver is
WEXT-native and its cfg80211 support is only a shim. Kernel stays on
board/gm8136/gm8135.generic.config (3.3.0).

`fw_env.config` is needed because the root is a read-only squashfs at boot and
this vendor flash map has no `rootfs_data` partition: uboot-tools finds the
environment but cannot cache it, and every `fw_printenv`/`fw_setenv` fails with
EROFS.

`/etc/wireless/usb` loads cfg80211 and mt7601sta for
`wlandev=mt7601sta-beewi-bc7pw`; everything else about the link is handled in the
driver and in the two overlays below.

`interfaces.d/wlan0` overrides the firmware's stanza. The stock one starts
wpa_supplicant with `-D nl80211,wext`, and this driver's cfg80211 support is a
shim that accepts a scan and never delivers a BSS, so the interface sat in
SCANNING and never associated. The override drives it with `-D wext`, the
driver's native path (the defconfig sets `BR2_PACKAGE_WPA_SUPPLICANT_WEXT`).

`S40network` overrides the eth0 handling. The stock script gives eth0 a static
address whether or not it has carrier, and this board enumerates a dead eth0, so
the camera came up dual-homed and on-subnet replies could leave by the port with
no cable. The override only addresses eth0 once it has carrier.

## Where it stands

- The link comes up end to end: the driver loads, the radio comes alive once the
  idle radio-off is disabled and the power mode is pinned to CAM, association
  and the 4-way handshake complete, and a DHCP lease follows.
- The root is writable and settings persist. `/init` matches this board's data
  partition, `USER` (mtd3), as well as `rootfs_data`, and mounts the union
  read-write.
- The MLME timer still oopses a few seconds in (below). It takes rate adaptation
  with it but leaves the link up.

## The two faults

**Dead scan: the driver switched its own radio off.** `STAMlmePeriodicExec()`
calls `RT28xxUsbAsicRadioOff()` as soon as the STA is idle and unassociated, and
`IDLE_ON()` means just that, so it fires on the first MLME tick of every boot:
radio off, bulk-in URBs cancelled, `fRTMP_ADAPTER_IDLE_RADIO_OFF` set, scan and
join bail out, and nothing wakes the radio again. The vendor meant to gate it on
`EnablePSinIdle`, a field that does not exist in this source, so it was
hard-wired to `1`. `0003` makes it `if ( 0`, and `0008` leaves the adapter in CAM
so the associated-link path cannot sleep either.

**Still open: the MLME timer oops.** A few seconds in, `RtmpTimerTask` calls
`MlmeDynamicTxRateSwitching()` and the call returns with the adapter pointer
replaced by MCS index bytes (`04 05 06 07`), so the caller faults on the next
load at that value plus `0x290`. The write behind it has not been found; the
rate code only stores to constant indices, and the same oops shows a different
victim in different builds, which is the shape of a write from outside the
frame.

## Driver patches

`0001`-`0008`. `0001` is required to build on this kernel (the `rtmp_cmd.h`
cfg80211 beacon guard has to be `(3,2,0)`); `0003` disables the idle radio-off
and `0008` pins the power mode to CAM; the rest fix the WEXT association path —
the link-down indication that fired while the link was coming up, the BSSID that
lost its middle two bytes in wireless events, and the two `SIOCGIWESSID` bugs.
None of them is board-specific, and the series is meant to go upstream once the
MLME fault is understood.

## Flashing

OpenIPC has no GrainMedia U-Boot, so the bootloader and its environment come
from a read-out of a working camera. `flash/bootloader.bin` is that read-out —
the first `0x60000` of the part: first-stage loader, U-Boot and its environment —
with the environment cleaned up: `init=/init` in `cmd1..cmd4` rather than the
vendor's `init=/squashfs_init`, `wlandev=mt7601sta-beewi-bc7pw`, and no SSID,
passphrase, upgrade URL or site-specific addresses baked in. Set `BOOT=` to
compose from a different read-out.

`flash/make-image.sh uImage.gm8135s rootfs.squashfs.gm8135s` composes the
flashable 16 MB image: `0xFF` fill, the boot region at `0x0`, the kernel at
`0x060000` and the rootfs at `0x260000`. Flash the result at `0x0`.
