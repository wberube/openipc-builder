# gm8135s_lite_beewi-bc7pw — bring-up notes

BeeWi BC7PW (also sold as **Wansview NCM703GC**) IP camera.

| | |
|---|---|
| SoC | GrainMedia **GM8135S** (family `gm8136`) |
| CPU | ARMv5TE (arm926ej-s), little endian |
| Kernel | Linux **3.3.0** (OpenIPC `linux` tarball, vendor config `board/gm8136/gm8135.generic.config`) |
| Flash | **16 MB** NOR (GD25Q128c), `BR2_OPENIPC_FLASH_SIZE="16"` |
| Wi-Fi | **MT7601** USB, driven by the **vendor `mt7601sta`** STA driver (`BR2_PACKAGE_MT7601U_OPENIPC=y` → package `mt7601u-openipc`) |
| Sensor | OV9732 (`sensor=ov9732` in U-Boot env) |
| Build token | `BOARD=gm8135s_lite_beewi-bc7pw` |
| Branch | `add-gm8135s-beewi-bc7pw` (fork: `wberube/openipc-builder`) |

Diagnosis constraint for this board: **there is no serial shell access** (board is
probed with a floating wire on a 0402 resistor, no soldering iron on hand).
Everything must be diagnosed **build-side** and observed on the console, or
reproduced from source. No on-device commands.

---

## 1. Device profile contents

```
br-ext-chip-grainmedia/configs/gm8135s_lite_beewi-bc7pw_defconfig
general/overlay/etc/fw_env.config
general/overlay/etc/wireless/usb
general/overlay/etc/network/interfaces.d/wlan0
general/overlay/etc/init.d/S41wifi-diag
general/overlay/usr/share/openipc/customizer.sh
general/scripts/excludes/gm8135s_lite.list
general/package/all-patches/mt7601u-openipc/0001-mt7601sta-lower-cfg80211-beacon-version-guard.patch
debug-archive/                     (diagnostics; archived, NOT applied)
```

Defconfig is cloned from the generic `gm8135_lite`; deltas:

- `BR2_OPENIPC_SOC_MODEL="gm8135s"`, `BR2_OPENIPC_FLASH_SIZE="16"`
- `RTL8188EU` dropped, `BR2_PACKAGE_MT7601U_OPENIPC=y` added
- kernel config stays `board/gm8136/gm8135.generic.config`, with **no config
  fragment** — the `gm8135-debug.fragment` lives in `debug-archive/` and is not
  applied (with it, the camera did not get past `CPU: Testing write buffer
  coherency: ok`)

### `/etc/wireless/usb`

```sh
#!/bin/sh
# BeeWi BC7PW (GM8135S)
if [ "$1" = "mt7601sta-beewi-bc7pw" ]; then
	echo 7 4 1 7 > /proc/sys/kernel/printk      # else the driver is silent
	echo "wireless: loading mt7601sta (console level raised)"
	modprobe cfg80211
	modprobe mt7601sta
	echo "wireless: modprobe done, netdevs: $(ls /sys/class/net | tr '\n' ' ')"
	exit 0
fi
exit 1
```

`wlandev=mt7601sta-beewi-bc7pw` is set by `customizer.sh` before `S40network`
reads it, so no extra `mt7601sta-generic` handler is needed.

### `/etc/network/interfaces.d/wlan0` and `/etc/init.d/S41wifi-diag`

Board-specific overrides of the firmware's Wi-Fi bring-up and a serial-console
state report. See section 4 for why they exist and what they change.

### `/etc/fw_env.config`

Must be shipped in the rootfs. The root is a **read-only squashfs** and this board
has **no `rootfs_data` partition**, so uboot-tools' env autodetect *finds* the
environment but cannot cache what it found; without this file every
`fw_printenv`/`fw_setenv` fails with EROFS and `wlandev`/`wlanssid`/`wlanpass`/
`sensor` are unreadable.

```
# device	offset		env_size
/dev/mtd0	0x40000		0x10000
```

Vendor NOR partitions (from `nor-flash`):

| mtd | range | name |
|---|---|---|
| mtd0 | `0x010000-0x060000` | `UBOOT` |
| mtd1 | `0x060000-0x260000` | `LINUX` |
| mtd2 | `0x260000-0x780000` | `ROOTFS` |
| mtd3 | `0x880000-0x1000000` | `USER` |
| mtd4 | `0x000000-0x1000000` | `ALL` |

### `customizer.sh`

Sets `upgrade` to the fork's release URL and `wlandev mt7601sta-beewi-bc7pw`,
`cli -s .video0.codec h264`. It also contains `wlanssid`/`wlanpass` **only in the
local working copy** — see the credentials policy below.

### `excludes/gm8135s_lite.list`

Placeholder; nothing board-specific stripped yet.

---

## 2. Flashing / image composition

OpenIPC ships **no GrainMedia U-Boot** (no release between `gk7605v100` and
`hi3516av100`), so the bootloader and its environment come from the user's own
read-out of the working camera, `BackupNowhereBeewiBC7PW.bin` (16 MB, untracked,
**contains Wi-Fi credentials** — do not commit it).

Layout used for the composed image:

| offset | contents |
|---|---|
| `0x000000` | first-stage loader + partition table |
| `0x010000` | U-Boot (`0x3d370` payload inside) |
| `0x050000` | saved U-Boot environment (CRC32 over `0x50004-0x60000`, LE at `0x50000`) |
| `0x060000` | `uImage.gm8135s` |
| `0x260000` | `rootfs.squashfs.gm8135s` |

Composition recipe (base filled with `0xFF`, first `0x60000` preserved from the
vendor image, then kernel and rootfs written at their offsets):

```sh
dd if=/dev/zero bs=1M count=16 | tr '\000' '\377' > new.bin
dd if=prev.bin      of=new.bin bs=1K count=384  conv=notrunc   # 0x000000..0x60000
dd if=uImage        of=new.bin bs=1K seek=384   conv=notrunc   # 0x060000
dd if=rootfs        of=new.bin bs=1K seek=2432  conv=notrunc   # 0x260000
```

Current artifact:
`archive/gm8135s_lite_beewi-bc7pw/202609130159/gm8135s_lite_beewi-bc7pw-nor.bin`,
16 777 216 bytes, md5 `13d52a2391d290b075dad6abc01a572c` (embeds the current
`openipc/output/images/rootfs.squashfs.gm8135s`, which carries the **vendor
prebuilt** `mt7601sta.ko` and a **wext-enabled** wpa_supplicant — see below).

### The `192.168.0.178` on wlan0 is not connectivity

Every boot that ends without a lease, `wlan0` comes up with `192.168.0.178/24`.
That is neither DHCP nor association: udhcpc's `leasefail` branch in
`usr/share/udhcpc/default.script` runs

    ifconfig $interface $(fw_printenv -n ipaddr || echo 192.168.1.10) netmask ...

so it applies the **u-boot env's** `ipaddr`, and that env came in with the boot
region merged from the vendor dump, still carrying the vendor's scheme
(`192.168.0.x`). The image that was flashed for the bring-up test also rewrites
`ipaddr`/`gatewayip` to sit on the operator's own LAN; those values are
**site-specific and deliberately not recorded here or anywhere in the profile**
— the profile sets no `ipaddr`/`gatewayip`/`netaddr_fallback`, so a build from
this tree keeps whatever the merged env already had. `serverip` is left alone
since only u-boot's net commands read it, and `netmask` was already
`255.255.255.0`. Consequence: a populated `ifconfig wlan0` or `wpa_cli status`
is **not** evidence of a working link.

### Wi-Fi module: the vendor prebuilt blob and its verbosity

The blob was built **with** `-DDBG`, not without it: `Debug` and `DebugFunc` are
the only entries in the driver's settable-parameter table that sit under
`#ifdef DBG` (`sta/sta_cfg.c:167`), and **both strings are present in the blob's
`.ko`** — as they are in our own build, so the package does pass `-DDBG`. What is
missing is not the code but the level: `RTDebugLevel` defaults to
`RT_DEBUG_ERROR` (1) (`os/linux/rt_linux.c:57`) while every message needed to
explain a dead scan is `RT_DEBUG_TRACE` (3). So `StaSiteSurvey`'s two early
returns ("Scanning now", "MLME busy") and `rt_ioctl_siwscan`'s
`req.essid_len`/`ScanType` trace are compiled in but silenced — which is why a
scan can be accepted and produce nothing, with no output to say so.

Raising the level needs the `Debug` settable parameter, reached through the
driver's proc tree: `proc_mkdir(PROCREG_DIR, NULL)` (`os/linux/rt_proc.c:502`),
with `PROCREG_DIR` defaulting to `"rt2880"`. The bring-up `/proc` sweep found no
such node, so the knob was unreachable on that boot. If it can be reached
(`/proc/rt2880/...`, or the equivalent private ioctl) the blob explains itself and
the module does not have to be swapped.

What the blob *does* expose is the non-DBG settable-parameter set — `SSID`,
`WPAPSK`, `AuthMode`, `EncrypType`, `NetworkType`, `WpaSupport`, `SiteSurvey`,
plus `stainfo`/`bainfo`/`show` — and `iwpriv`'s syntax is `<Name>=<Value>`
(`RTMPSTAPrivIoctlSet`'s caller splits on `'='`). `set WpaSupport=0` selects the
driver's **own** supplicant, so the driver can be driven directly with
`set SSID=`/`set WPAPSK=`/`set AuthMode=WPA2PSK`/`set EncrypType=AES`, and
`set SiteSurvey` (which takes no value and calls `StaSiteSurvey` directly)
triggers a scan. The diag now stops wpa_supplicant and does exactly that.

`general/overlay/lib/modules/3.3.0/extra/mt7601sta.ko` is the module read out of
`BackupNowhereBeewiBC7PW.bin`, md5 `0d271ec0a968c5b4edff1efadf00b3ed`, 1 319 900
bytes, `vermagic=3.3.0 preempt mod_unload ARMv5`, GCC 8.4.0,
`version=JEDI.MP1.mt7601u.v1.12.2.3`, 16 `cfg80211_*` imports, all resolvable
against our `cfg80211.ko`.

**Correction: this is not a vendor/factory binary.** `BackupNowhereBeewiBC7PW.bin`
is a snapshot of an earlier *builder-produced OpenIPC* image, not factory
firmware. Its rootfs at `0x260000` is an OpenIPC rootfs — its
`/etc/wireless/usb` dispatcher understands `mt7601sta-generic` and its
`interfaces.d/wlan0` uses `fw_printenv -n wlanssid` — and its kernel partition at
`0x60000` starts with a uImage header (`27 05 19 56`), i.e. the same builder
output. The GCC 8.4.0 stamp is the tell: this is an older build of *this* driver,
not the factory's. So it carries the same source-level defects as our build, and
"vendor blob" is a misnomer throughout this document. What it is *not* is the
matched partner of a different kernel: the dump's `cfg80211.ko` (190 524 B) and
ours (192 792 B) export an **identical** 223-symbol set and import an identical
122, so the ~2 KB size gap is compiler/flag noise, not an ABI difference — a
cfg80211 swap is not a lever here.

The upside of the correction: nothing is lost by retiring the blob, because it is
our own driver. A defect inside it can only be fixed by building from source.

It reaches the rootfs through the normal rootfs overlay, i.e. **after** the
`mt7601u-openipc` package installs its own build of the same file, so the blob
wins. The package stays enabled because it is what installs
`/etc/mediatek/MT7601USTA.dat`, which the blob reads at init.

Verified in the built squashfs (not just the target dir):
`md5(unsquashfs -cat .../lib/modules/3.3.0/extra/mt7601sta.ko)` == `0d271ec0…`,
and `modules.dep` lists `extra/mt7601sta.ko: kernel/net/wireless/cfg80211.ko`.

### U-Boot environment

The environment in the image has been **hex-edited** relative to the vendor
default. Points that matter:

- `cmd1..cmd4` must use **`init=/init`**, not the vendor `init=/squashfs_init`.
  `/squashfs_init` does not exist in an OpenIPC rootfs, so the kernel falls back
  to busybox `/sbin/init`, OpenIPC `/init` never runs, overlayfs is never set up,
  `/` stays read-only and everything fails with EROFS.
- Keep `wlandev=mt7601sta-beewi-bc7pw` and `sensor=ov9732`.
- **`upgrade` must stay absent.** It is unset by default and only the customizer
  sets it on first boot; don't bake it in.
- **`ipaddr`/`gatewayip` must be on the operator's LAN.** These are site-specific
  and are *not* part of the profile and not recorded here — set them in the
  flashed env only. udhcpc's `leasefail` branch applies `ipaddr` to whichever
  interface failed to get a lease, so a vendor-subnet value here hands wlan0 a
  bogus address that looks like connectivity. See the `192.168.0.x` section
  above.

---

## 3. Kernel / driver version-guard decisions

- **`include/rtmp_cmd.h:383` must be `KERNEL_VERSION(3,2,0)`.** GrainMedia
  backported the newer `cfg80211_beacon_data`/`beacon_parameters` fields into
  their 3.3 kernel and `cfg80211drv.c` already uses `(3,2,0)`. Reverting to the
  upstream `(3,4,0)` fails to build (`CMD_RTPRIV_IOCTL_80211_BEACON` has no member
  `ssid_len`); moving `cfg80211drv.c` to `(3,4,0)` also fails (its `#else`
  fallback references undeclared `ssid_ie` — dead code). Patch
  `mt7601u-openipc/0001-mt7601sta-lower-cfg80211-beacon-version-guard.patch`.
- The kernel is a **forward-port, not vanilla 3.3** (3.15-era skb layout —
  `NET_SKBUFF_DATA_USES_OFFSET=1`, `sk_buff_data_t tail` as a 32-bit offset —
  backported cfg80211). Every `LINUX_VERSION_CODE` guard in this 2013 driver is
  suspect. The skb-tail trap is already handled in our fork, which uses
  `skb_tail_pointer()`/`skb_set_tail_pointer()`.
- The glutinium patch series (008 etc.) is **not** needed: 008 touches only a
  `#ifdef RT_BIG_ENDIAN` hunk (dead on our little-endian build) plus a
  `UINT32`→`UINT16` local, and patch 001's substantive hunk is the skb tail
  already covered above.

### Driver patches present

| patch | purpose | verdict |
|---|---|---|
| `0001-...beacon-version-guard.patch` | `rtmp_cmd.h` 3.4.0 → 3.2.0 | **required to build** |
| `0002-rt_os_util-disable-wext-assoc-ie-event.patch` | no-ops `wext_notify_event_assoc()` | **no effect on the crashes; candidate for removal.** Its comment (that this function's own frame corrupts its caller's stack) is wrong — that frame was a *victim*, not the cause |
| `0003-assoc-bound-rsn-ie-copy.patch` | bounds `pEid->Len + 2` against `MAX_LEN_OF_RSNIE` before the RSN/WPA/WAPI IE copy | keep — real 2-byte peer-controlled overflow (`Len` is `u8`, so up to 257 into a 255-byte bound) |

---

## 4. Wi-Fi fault investigation (main blocker)

Symptom: with `init=/init` the root is writable and `wlan0` comes up, then
**within seconds of association/DHCP** the kernel dies. Successive failures had
different signatures — a wild-pointer oops, slab corruption, and stack-protector
panics — in **different functions and different tasks**.

### Observed failures

| log | symptom |
|---|---|
| A | `Unable to handle kernel paging request at virtual address 98128c08` (PC `98128c08`), `LR is at __schedule+0x300`, process `RtmpMlmeTask` |
| B | `PC is at 0x98128c08`, `LR is at queue_work+0x30/0x54` — a corrupted `work_struct` function pointer being called |
| C | `stack-protector: Kernel stack is corrupted in: 7f0b6868` |
| D | `stack-protector: guard=… @8041e008 ret=7f0b0ec4 sp=…` + 32-word dump |
| E | `DEBUG_SLAB` flood (`check_slabp`, `debug_objects_replace_static_objects`) → panic |

### Resolving the panics

A module-map print (`cat /proc/modules` + `/sys/module/mt7601sta/sections/*`) was
added temporarily to `/etc/wireless/usb` so the module-space panic addresses could
be resolved. With it:

| panic address | `mt7601sta.text` | offset | symbol |
|---|---|---|---|
| `0x7f0b6868` | `0x7f04e000` | `0x68868` | `wext_notify_event_assoc+0x84` |
| `0x7f0b0ec4` | `0x7f059000` | `0x57ec4` | **`MlmeDynamicTxRateSwitching+0x6f8`** |

Note that the same panic address with a *different* module base resolves to a
completely different function — earlier attempts that assumed a base landed in
the P2P block (`P2P_GoStartUp`, `PeerP2pProbeReq`, `WscStop`, …) and were
**artifacts of a wrong base**, not real candidates.

`MlmeDynamicTxRateSwitching+0x6f8` is exactly the `bl __stack_chk_fail` in that
function's epilogue, so there is no ambiguity about which frame was smashed. The
dump's own addresses agree on the chain:
`RtmpTimerQThread+0 → RtmpTimerQHandle+0x128 → MlmePeriodicExec+0x1e0 →
MlmeDynamicTxRateSwitching` — i.e. the **~1 Hz periodic MLME / rate-adaptation
timer**, which is why it dies a few seconds after the interface comes up.

Frame layout (from disassembly of `mt7601sta.ko`, `rate_ctrl/alg_legacy.c:719`):

```
sub sp, sp, #100            ; 100-byte frame
str r3, [sp, #92]           ; stack-protector canary at sp+92
...
add r2, sp, #68 ; bl MlmeGetSupportedMcs    ; CHAR mcs[24] at sp+68..sp+91
add r2, sp, #68 ; bl MlmeSelectTxRate
```

`CHAR mcs[24]` is therefore **flush against the canary**, and the bytes that
landed on the canary were `0x03020100` / `0x07060504`, i.e. `00 01 02 03 04 05 06 07`
— the shape of an MCS/index list, and `mcs[0..7]`'s own contents for
`RateSwitchTable11N1S` (entries 0..7 are MCS 0..7).

### Ruled out (with the check used)

- `MlmeGetSupportedMcs()` / `MlmeGetSupportedMcsAdapt()` write only fixed indices
  ≤ 23 (`ra_ctrl.c:508-568`, `alg_grp.c:291`) — cannot reach `sp+92`.
- `MlmeSelectTxRate()` only *reads* `mcs[]`.
- Prototypes match their implementations (`drs_extr.h:154/159/341`).
- `PTX_RA_LEGACY_ENTRY`'s hard-coded 5-byte stride is correct:
  `RTMP_RA_LEGACY_TB` is five `UCHAR`s (no padding).
- No store in `MlmeDynamicTxRateSwitching` reaches `sp+92`; the highest is `sp+64`.
- The adapter block **is** zeroed: `AdapterBlockAllocateMemory()` does
  `vmalloc()` followed by `NdisZeroMemory(*ppAd, SizeOfpAd)` (`rt_linux.c:2077-2080`).
  (An earlier theory — uninitialised pointer fields being freed — is therefore dead.)
- The vendor-request path cannot write a dead stack frame: `RTUSBReadMACRegister()`
  reads into its own `localVal` and copies out *after* the synchronous completion,
  and the DMA target is the kmalloc'd `pAd->UsbVendorReqBuf` (2048, semaphore-guarded).
- No caller pointer is stashed into the `pAd` for deferred use in the ioctl/sta/cfg80211 paths.
- `DFS_EVENT_BUFFER_SIZE` (384) fits the bounce buffer; vendor-request lengths are small.
- `DEBUG_SLAB` is unusable here (see below); `DEBUG_OBJECTS*` also misbehaved and is off.

### Working hypothesis and current fix attempt

The corruption is **not** a bounded write in the victim function — the victim
frame changes between logs *and* between tasks (`wext_notify_event_assoc` is
called in the wpa_supplicant ioctl context, `MlmeDynamicTxRateSwitching` on the
MLME timer thread). That is the signature of a deep call chain overflowing an
**8 KB kernel stack** and writing into *adjacent* memory (another task's stack, or
a slab — matching the slab corruption and the garbage `work_struct` function
pointer that `queue_work` jumped to).

**Correction to the evidence above (verified in the source):** in
`arch/arm/kernel/traps.c:247` the oops prints `thread + 1`, i.e. the address just
past `struct thread_info`, which sits at the **bottom** of the task stack. So
`stack limit = 0x83f02270` is `base + sizeof(struct thread_info)` (624 B, with
the base 8 KB-aligned at `0x83f02000`), and `sp = 0x83f03e60` means the MLME task
was only **~416 bytes deep** on its stack — nearly idle, not nearly full. The
same ~416-byte depth shows up in the later oops (`sp=0x838ade60`,
`stack limit=0x838ac270`). The "deep call chain overflowing an 8 KB stack"
reading is therefore wrong, and so is the frame-relative overflow it implies:
two *independent* victims in *different* tasks (`wext_notify_event_assoc` in the
wpa_supplicant ioctl context, `MlmeDynamicTxRateSwitching` on the MLME timer
thread) cannot both be upward writes from their own callees. The write has to be
**absolute-address** — into whichever page happens to neighbour the overflowing
buffer — and `thread_info->cpu_context`, which sits at the very bottom of a task
stack, is exactly what such a write reaches.

**Where the wild PC comes from:** `LR = __schedule+0x300` resolves in this
vmlinux to `0x80267ef0`, the instruction right after `bl sub_preempt_count`; the
block ends in `pop {r4-r9, sl, fp, pc}` (`__schedule+0x30c`). `pop` does not
touch `LR`, which is why the wild PC arrives with such an unremarkable `LR`: the
return address was read off a clobbered stack slot. The registers at fault still
hold a scan request — `r4..r7` decode to `00 09`, then the operator's 9-byte
SSID (deliberately not reproduced here), then `01`, i.e. the
`[Bssid][SsidLen=9][Ssid][ScanType=1]` shape of `MLME_SCAN_REQ_STRUCT` — so the
corruption happens while an SSID-bearing command is in flight.

**Mechanism to chase:** an unbounded length driving a copy, so a wrong length
field becomes a huge `memcpy` into a small buffer. The operator already pointed
at this with the glutinium `008-more-big-endiand-fixes.patch` (a length read in
the wrong byte order turns `0x0009` into `0x0900`), and the `r4..r7` residue of
an SSID length plus its string is consistent with it. `RSN_IE`
(`sta/assoc.c:1541/1551/1562`, copying `pEid->Len + 2` into `MAX_LEN_OF_RSNIE`)
is a genuine overflow but it lands in a *struct*, not on a stack, so it is not
this one — consistent with the canary merely moving when it was bounded.

**Root cause of the dead scan (confirmed, 2026-09-19):** the radio is switched
off by the driver itself, before it can ever associate. `STAMlmePeriodicExec()`
(`common/mlme.c:1472`, `#ifdef RTMP_MAC_USB`) reads

```c
	/* If station is idle, go to sleep*/
	if ( 1
	/*	&& (pAd->StaCfg.PSControl.field.EnablePSinIdle == TRUE)*/
		&& (pAd->StaCfg.WindowsPowerMode > 0)
		&& (pAd->OpMode == OPMODE_STA) && (IDLE_ON(pAd))
		&& (pAd->Mlme.SyncMachine.CurrState == SYNC_IDLE)
		&& (pAd->Mlme.CntlMachine.CurrState == CNTL_IDLE)
		&& (!RTMP_TEST_FLAG(pAd, fRTMP_ADAPTER_IDLE_RADIO_OFF)))
	{
		RT28xxUsbAsicRadioOff(pAd);
		DBGPRINT(RT_DEBUG_TRACE, ("PSM - Issue Sleep command)\n"));
	}
```

and `IDLE_ON(_p)` is `(!INFRA_ON(_p) && !ADHOC_ON(_p))` — *not associated*, with no
timer. The guard the vendor intended (`EnablePSinIdle`) does not exist anywhere in
this source, so the test is hard-wired to 1 and the branch fires on the first MLME
tick of every boot, while the station is still trying to associate. It runs
`ASIC_RADIO_OFF` and cancels the pending bulk-IN URBs — the

```
unlink cmd rsp urb
```

line in the log, from `RTUSBCancelPendingBulkInIRP()` — and sets
`fRTMP_ADAPTER_IDLE_RADIO_OFF`, which `sta/sync.c` and `sta/connect.c` test and bail
out on. Nothing wakes the radio again, because waking happens on transmit and an
unassociated station has nothing to transmit. Hence: `RX packets` frozen,
`TX packets:0`, `get_site_survey` empty header only, `iwlist scan` "No scan
results", and association that never starts — a bootstrapping deadlock.

It is also the likely origin of the `RtmpMlmeTask` oops: the MLME is the task that
issues the radio-off and then runs the sync/scan state machine that has just been
told to stop, so the corruption the canary reported is plausibly downstream of
this, not an independent bug.

Why it stayed hidden: the driver builds with every `DBGPRINT` compiled out (they
exist only `#ifdef DBG`, and the package's `EXTRA_CFLAGS` never define `DBG`), so
`iwpriv wlan0 set Debug=3` sets `RTDebugLevel` and prints nothing; the only output
is a handful of bare `printk`s. `0004-mt7601u-enable-DBG-prints.patch` adds
`-DDBG`.

Fixed by `0005-mt7601u-disable-idle-radio-off.patch`, which turns the branch into
`if ( 0` (the field the test names does not exist, so it cannot be gated on it),
plus `PSMode=CAM` in `/etc/wireless/usb`, which both covers this and stops
`MlmeCheckPsmChange()` from putting an *associated* link into `PWR_SAVE`.
`WindowsPowerMode == Ndis802_11PowerModeCAM` (0) short-circuits the branch, but it
cannot be relied on alone: it is a runtime setting that lands seconds after the
MLME has already fired. (`PSMode=CAM` is in fact already the default in
`MT7601USTA.dat`, which is why the flag never saved it.)

**Confirmed on hardware.** With `0005` in place the radio comes alive: the scan
walks channels 1-13, `get_site_survey` returns three BSSes (the operator's AP at
-71 dBm plus two neighbours — their SSIDs are deliberately not reproduced here),
the ASSOC exchange completes (`ASSOC - receive
ASSOC_RSP to me (status=0)`, and `stainfo` shows the AP at AID 1, MCS 7, 72 Mb/s), `TX packets` goes from 0 to 17 and the fake `-80` beacon
RSSI is gone. No `unlink cmd rsp urb`. The empty survey was the idle radio-off and
nothing else.

**What the same boot also shows** is that the `RtmpMlmeTask` oops is separate and
still there, now pinned precisely: the last output before the fault is the peer's
HT dump (`Peer - MODE=2, BW=0, MCS=7`) and `AssocPostProc():=> Store RSN_IE`, i.e.
the moment association completes and the WPA2 4-way handshake begins. The oops is
byte-for-byte identical to the one the vendor blob produced (same `PC 0x98128c08`,
same stack, `LR __schedule+0x300`), so it is deterministic and it is in this
source. The `MlmeEnqueueForRecv(): full and dropped` flood that follows is only
the corpse: the MLME task is dead so nothing drains its RX queue, and it prints at
`RT_DEBUG_INFO`/`TRACE`, so it appears because `Debug=3` is set and would be
silent otherwise.

What has been tried against it, and what that settled:

* `0003-assoc-bound-rsn-ie-copy.patch` (moved out of `debug-archive/`) bounds the
  three `NdisMoveMemory` copies in `AssocPostProc` — `pEid->Len + 2` is
  peer-controlled and lands in a `MAX_LEN_OF_RSNIE` (255) field. Latent with this
  AP (its RSN IE is 22 bytes) but it is on the exact path that dies.
* **The cfg80211 association enqueue — exonerated on hardware.** A patch removing
  the `RTEnqueueInternalCmd(CMDTHREAD_CONNECT_RESULT_INFORM, …)` call from
  `PeerAssocRspAction()` (the last thing the MLME task does before the fault) was
  built and booted. The fault came back byte-identical — same `PC 0x98128c08`, same
  `LR __schedule+0x300`, same registers (`r4=45540900 r5=3753554c r6=01393233
  r7=000bcf6a`), same stack residue, and the module did load (`1627486` in
  `/proc/modules`). So the cfg80211 glue on that path is not the corruptor, and the
  patch was retired (the resulting module is byte-identical to the build without it).
* **Forcing 11g — re-test in progress; the earlier conclusion is not reproducible.**
  `WirelessMode=4` (`PHY_11G`/`WMODE_G`) makes `WMODE_CAP_N()` false, so the STA
  sends no HT capability, the driver parses no HT information from the response, the
  entry is never upgraded to HT and the per-second rate update stays legacy. An
  earlier session concluded this does not clear the fault, but no log supports that
  conclusion: **every boot on record** reports `cfg_mode=9`, `1. Phy Mode = 14` and
  `iwconfig` `B/G/gN(14)` — HT still active — and the last output before every fault
  is the peer's HT dump. `0006-mt7601u-force-11g.patch` is therefore back in the tree
  for a controlled re-test, and a run only counts as a test of this if the log shows
  **`cfg_mode=4`, no `Peer - 11n HT Info` block, and `iwconfig` `B/G(4)`**. The
  stale-patch trap above is exactly how such a build can look applied when it is not.
* One candidate checked and cleared: `PeerAssocRspSanity()` copies a fixed
  `SIZE_HT_CAP_IE` (26) bytes into `pHtCapability` guarded only by `pEid->Len` — a
  stack-overflow shape, and the write is into the MLME task's own frame. But the
  packed `HT_CAPABILITY_IE` is `HtCapInfo(2) + HtCapParm(1) + MCSSet(16) +
  ExtHtCapInfo(2) + TxBFCap(4) + ASCap(1) = 26`, i.e. exactly `SIZE_HT_CAP_IE`, so it
  is struct-sized, not an overflow. (`IE_ADD_HT` uses `sizeof()` regardless.)

### Separately: the vendor modules can now panic the boot

On the `#30` kernel the boot reached the WIFI DIAG block and then died in the vendor
module load:

```
insmod: page allocation failure: order:3, mode:0x20
[ms]ms_zalloc:66: kmalloc fail. size(32768)
Damnit from (ms_zalloc+0x9c/0x194 [ms])   <- from gs_driver_init
Kernel panic - not syncing: Error allocate proc buf
```

`Mem-info` reported `Normal free:1584kB` against `min:1016kB`: the board is 64 MB with
34 MB reserved for gmmem, and a 32 KB *contiguous* allocation no longer exists. The
previous boot hit the same class of failure (`order:5` in `vpd`) and survived, so this
is fragmentation-dependent rather than deterministic, and it is unrelated to the MLME
fault — but it means a wedged boot may now end in a reboot instead of a shell.
When that happens the log is still usable: the `cfg_mode=` line at driver load, and
the HT dump (or its absence) at association, both appear long before the panic.


### The dumps contain no OEM MT7601 driver

All seven local dumps were walked (cramfs dir entries and squashfs metadata
tables are readable even though file *data* is compressed), looking for a
Wi-Fi module to use as a known-good reference:

| dump | SoC | rootfs | Wi-Fi module |
|---|---|---|---|
| `..._GM8135_WiFi` (8 MB) | GM8135 | cramfs | `8188eu.ko` (RTL8188EU) |
| `longse_blue1/blue2/black1` (16 MB) | GM8136 | squashfs | none (46 GrainMedia drivers only) |
| `jco1` / `jco2` (8 MB) | GM8136 | squashfs / jffs2 | none (28 GrainMedia drivers only) |
| `BackupNowhereBeewiBC7PW.bin` | GM8135S | squashfs | `mt7601sta.ko`, 1 319 900 B, md5 `0d271ec0…` |

The *only* MT7601 binary anywhere is the one in our own backup image, and it is
not a vendor reference: same `version=JEDI.MP1.mt7601u.v1.12.2.3` and same
`vermagic`. Comparing it against our build is therefore a build-vs-build
comparison, and it is informative:

| | backup module | our build |
|---|---|---|
| size | 1 319 900 | 1 916 372 |
| compiler | Buildroot `-g4783f48`, GCC **8.4.0** | Buildroot `-gefad351`, GCC **13.3.0** |
| `cfg80211drv.c` SSID branch | **`#else`** (no `CFG: Invalid SSID len` / `CFG : SSID:` strings; `cfg80211_parsing_ie` present) | **`>= 3.2`** (both strings present) |
| `vermagic` | `3.3.0 preempt mod_unload ARMv5` | same |
| `version=` | `JEDI.MP1.mt7601u.v1.12.2.3` | same |

So the same defect reproduces across **two different compilers** (GCC 8.4 and
13.3) and **two different guard arrangements** of the same SSID block — the
backup was compiled taking the `#else`/`cfg80211_parsing_ie` path, ours taking the
`>= 3.2` path that `0001` enables. Neither arrangement avoids the crash (the
backup's oops was byte-for-byte identical: same `PC 0x98128c08`, same `LR
__schedule+0x300`). That kills two standing theories at once: the fault is not a
wrong `cfg80211drv.c` guard (so OpenIPC firmware#1771's "change 3.2.0 → 3.4.0"
fixes the *compile*, not this), and it is not a modern-GCC miscompile.


**Mitigation considered (not a cure):** raise `THREAD_SIZE` to 16 KB —
`THREAD_SIZE_ORDER` 1 → 2, `THREAD_SIZE` 8192 → 16384. It was live for a while at
`general/package/all-patches/linux/0001-arm-raise-kernel-stack-to-16k.patch`,
then archived to `debug-archive/` when the Wi-Fi diag image was rebuilt: it only
ever helps while a canary exists to catch the overflow, and it belonged to the
batch that broke early boot. The live tree now carries nothing but the stock
`gm8135.generic.config` — verified `THREAD_SIZE_ORDER` is 1,
`CONFIG_CC_STACKPROTECTOR` is not set, and neither `vmlinux` nor `mt7601sta.ko`
references `__stack_chk`. The stray `-fstack-protector` in `arch/arm/Makefile`
ships in the kernel source and is inert.

If that patch is ever restored, note that it *is* detectable in the built kernel
rather than only in the source: the linker script aligns `init_thread_union` with
`. = ALIGN(THREAD_SIZE)`, so `nm vmlinux` shows `init_thread_union` at `0x4000`
in a 16 KB-aligned address instead of `0x2000`.

This only helps if the offending write lands within ~8 KB past the buffer. If the
length is wrong by orders of magnitude it changes nothing, and the real fix is
source-side — which requires building the driver, hence the provenance
correction above.

### Diagnostics: archived, not applied

All of the instrumentation (`-fstack-protector-all`, the canary frame dump, the
debug fragment, the 16 KB stack patch, and the driver-side `0002`/`0003` patches)
stays in `debug-archive/`, with restoration steps in
`debug-archive/README.md`. The kernel is back on the stock
`gm8135.generic.config` with nothing else applied.

The batch as a whole stopped the camera getting past `CPU: Testing write buffer
coherency: ok`, so it was pulled. The 16 KB stack half was kept live for a while
on the theory that the fragment (`CONFIG_CC_STACKPROTECTOR` / `DEBUG_OBJECTS`,
which panics before the console is up on this vendor kernel) was to blame rather
than the stack size — that attribution was never verified on hardware, and it has
since been archived too so that a stock build is a stock kernel.

Three driver patches stay in the tree: `0001-...beacon-version-guard.patch` (the
package does not compile without it), `0004-mt7601u-enable-DBG-prints.patch`
(build with `-DDBG`, without which every `DBGPRINT` is a no-op and the driver
cannot explain itself at all) and `0005-mt7601u-disable-idle-radio-off.patch`
(the fix above).

The vendor `mt7601sta.ko` is no longer shipped. It is built from this same source
and so carries the same idle-radio-off bug, the ROOTFS partition (5,373,952 bytes
between `0x260000` and `0x780000`) cannot hold it alongside the 1.9 MB `-DDBG`
build, and the log that identified the bug was produced by the blob itself. It is
kept outside git at `archive/gm8135s_lite_beewi-bc7pw/vendor-mt7601sta-blob.ko`.
Dropping `-DDBG` once the wireless works frees most of a megabyte again.

That message is worth placing precisely: `check_writebuffer_bugs()` is
`check_bugs()` on ARM, which is the **last** call in `start_kernel()` before
`rest_init()`. So it is not an early-MMU hang — the kernel has finished all early
setup and gone silent entering the init thread, i.e. in the initcalls, the root
mount or `/init`. Worth remembering when reading a log that stops there: nothing
before the root mount can be blamed on the rootfs.

To resolve a **future** module-space panic address, the module map has to be
re-added (it was removed when the fix build was prepared); the canary
instrumentation alone prints `ret=<addr>` without a base.

**Do not enable `CONFIG_DEBUG_SLAB`**: on this vendor SLAB it misfires from early
boot — it reports "Slab corruption" for core caches before the console is enabled
and long before any driver loads — and its `check_slabp` BUG panics during
`debug_objects_replace_static_objects`, killing the boot. It is not reporting our
fault.

### Why the boot log shows no Wi-Fi activity

The log is *silent* about the driver; that is not proof it failed.

- The image ships `/etc/sysctl.conf` with **`kernel.printk = 3 3 1 3`**, applied
  by sysctl before `S40network`. From that point **only KERN_ERR and above reach
  ttyS0**. The driver's load banner, its `usbcore: registered new interface
  driver rt2870` line, EEPROM/firmware complaints and scan results are all
  KERN_INFO/KERN_WARNING — filtered out.
- Userspace output (wpa_supplicant, udhcpc) is not filtered, which is why the
  log shows wpa_supplicant starting and nothing at all from the driver.

So `modprobe mt7601sta` succeeding with no console output is the expected
appearance. `/etc/wireless/usb` now raises the console level before the
modprobes, and `S41wifi-diag` reports the state (including `dmesg`) after
`S40network`.

### What is actually wrong with the Wi-Fi bring-up

Established from the log and from the driver sources:

- `ifup wlan0` definitely ran — wpa_supplicant is started *only* from
  `/etc/network/interfaces.d/wlan0` and nothing else in the rootfs starts it.
  So `wlandev` was read back correctly, `/etc/wireless/usb` matched and both
  modprobes ran.
- The interface really is `wlan0`, not `ra0`: `INF_MAIN_DEV_NAME` is `"wlan"`
  when `RT_CFG80211_SUPPORT` is defined (the package builds it that way),
  `"ra"` otherwise, and the module contains no bare `ra` string.
- `wlanssid`/`wlanpass` are present, so the generated
  `/tmp/wpa_supplicant.conf` is not the problem: they are in the image's U-Boot
  environment (values not reproduced here), inherited from the read-out, and the
  customizer sets them again on first boot.
- The driver's own defaults in `/etc/mediatek/MT7601USTA.dat` are the upstream
  template — `SSID=11n-AP`, `AuthMode=OPEN`, `NetworkType=Infra` — i.e. not
  this camera's AP.
- The previous rootfs the camera ran (extracted to `/tmp/bcroot`) is the same
  OpenIPC arrangement: same stanza, same .dat, no `wireless.sh`, and no
  `/etc/firmware` or `e2p.bin`, so there is no older working configuration to
  copy from.

The remaining suspect is **which control path wpa_supplicant uses**. The
firmware stanza starts it with `-D nl80211,wext`, nl80211 first. This vendor
driver is WEXT-native — it is compiled with `-DWPA_SUPPLICANT_SUPPORT
-DNATIVE_WPA_SUPPLICANT_SUPPORT` — and its cfg80211 support is a shim (the
`cfg80211drv.c` that had to be version-guarded to build at all). When nl80211
attaches but its scan/connect shim never delivers, wpa_supplicant fails
**silently** at default verbosity (scan errors are MSG_DEBUG), and the visible
result is exactly the log we have: no association attempt, no DHCP lease.

Changes applied to test that, all in the one image:

1. `interfaces.d/wlan0`: `-D wext,nl80211` (prefer the driver's native path,
   keep nl80211 as fallback), `-d` so wpa_supplicant's own scan/assoc messages
   reach the console, and `ctrl_interface=` so `wpa_cli` works.
2. `etc/wireless/usb`: raise `kernel.printk` before the modprobes.
3. `S41wifi-diag`: env values, loaded modules, netdevs, the generated conf
   (psk masked), `/proc/net/wireless`, driver proc entries, `wpa_cli
   status`/`scan`/`scan_results`, and the driver's `dmesg` lines.

If it still does not associate, that report names the failing step: no `wlan0`
means the driver did not bind (its dmesg will say why); empty `scan_results`
means RF/EEPROM or the driver's scan; results present but no association means
the connect path.

### What that boot actually showed

- The driver loads and binds: `rtusb init rt2870 --->`,
  `usbcore: registered new interface driver rt2870`, netdevs `lo p2p0 wlan0`,
  and it calibrates the RF (`LDO_CTR0(6c) = a64799` / `a6478d`, `PMU_OCLEVEL 6`,
  `NumOfChan ===> 14`).
- wpa_supplicant attaches to `wlan0` and triggers scans (`wpa_cli scan` → `OK`),
  but **`scan_results` stays empty and no association is ever attempted**, so
  udhcpc never gets a lease.
- `-D wext,nl80211` did **not** use wext — every driver call in the log is
  `wpa_driver_nl80211_*`.

### Why wext was skipped, and why that is the likely blocker

The image's wpa_supplicant 2.10 is built with wext **off**:
`output/build/wpa_supplicant-2.10/wpa_supplicant/.config:29` has
`#CONFIG_DRIVER_WEXT=y` against `CONFIG_DRIVER_NL80211=y`. Buildroot's
`package/wpa_supplicant/wpa_supplicant.mk:44` disables `CONFIG_DRIVER_WEXT`
unless `BR2_PACKAGE_WPA_SUPPLICANT_WEXT` is selected, and our defconfig does not
select it. So `-D wext,nl80211` silently falls through to nl80211 — into the
driver's cfg80211 shim.

That matters because the driver registers a full WEXT handler table
(`rt28xx_iw_handler_def`, `.standard = rt_handler`, `sta_ioctl.c:2492-2498`)
including `SIOCSIWSCAN` (`rt_ioctl_siwscan`) **and** `SIOCGIWSCAN`
(`rt_ioctl_giwscan`, which copies the driver's own BSS table out to userspace).
Over WEXT the scan results come from that table; over nl80211 they have to go
through `cfg80211_inform_bss_frame`/`cfg80211_scan_done` (`CFG80211OS_Scaning`,
`rt_linux.c:3337`), which is where the zero-BSS result comes from. The driver is
also built with `-DNATIVE_WPA_SUPPLICANT_SUPPORT` — the WEXT wpa_supplicant
interface is its intended path.

**Applied.** The kernel side was already complete for this
(`CONFIG_WEXT_CORE=y`, `CONFIG_WEXT_PRIV=y`, `CONFIG_WEXT_PROC=y`,
`CONFIG_CFG80211_WEXT=y` in `board/gm8136/gm8135.generic.config`, and the
driver compiles its `SIOCSIWGENIE`/`SIOCSIWMLME` handlers because
`autoconf.h` defines `CONFIG_WEXT_PRIV`). What was missing was user space:

1. `BR2_PACKAGE_WPA_SUPPLICANT_WEXT=y` in the device defconfig. Buildroot
   otherwise emits `#CONFIG_DRIVER_WEXT=y` and `-D wext` is a no-op.
   Verified after the rebuild:
   `output/build/wpa_supplicant-2.10/wpa_supplicant/.config:29` is now
   `CONFIG_DRIVER_WEXT=y` alongside `CONFIG_DRIVER_NL80211=y`, and the installed
   binary carries the wext code (`SIOCSIWSCAN`/`SIOCGIWSCAN` strings, absent
   before).
2. `interfaces.d/wlan0`: `-D wext` (no nl80211 fallback, so the log cannot be
   ambiguous about which driver attached) and `-f /tmp/wpa.log`. The `-f` matters:
   `-B` daemonizes and a daemonized wpa_supplicant writes its log to `/dev/null`,
   which is why every previous boot showed nothing after `Daemonize..` and why
   `-d` looked useless.
3. `S41wifi-diag` additionally runs `iwconfig wlan0`, a bounded
   `iwlist wlan0 scan` (the driver's WEXT scan path, independent of
   wpa_supplicant), dumps `/tmp/wpa.log`, checks whether udhcpc is still alive,
   and — if `wpa_state=COMPLETED` — asks for a lease itself with
   `udhcpc -i wlan0 -n -q -t 4`, since `ifup` starts udhcpc before association
   exists and it may have given up by then.

---

## 5. Credentials policy

- `wlanssid`/`wlanpass` are kept **in the local working `customizer.sh`** so the
  user's own build keeps working, but they must **never** be committed or pushed.
- An earlier commit on the fork (`e81a6f0`) briefly contained them; it was
  superseded and force-pushed, and the Wi-Fi password **should still be rotated**.
- `BackupNowhereBeewiBC7PW.bin` also contains credentials and is untracked.

## 6. Commit policy

**No co-authoring trailers, under any circumstances.**

---

## 7. Open items

- [ ] Flash the current image (vendor blob + wext-enabled wpa_supplicant, md5
      `1e48462d288baa80f65444a51bf33396`) and read the `WIFI DIAG` block on ttyS0.
- [x] Enable `BR2_PACKAGE_WPA_SUPPLICANT_WEXT=y` and drive the driver's native
      WEXT scan/connect instead of the cfg80211 shim (see section 4).
- [ ] If wext also fails to see the AP (`iwlist wlan0 scan` empty), the fault is
      below wpa_supplicant: driver link/EEPROM, then the `MT7601USTA.dat`
      defaults.
- [ ] Once association works, delete `S41wifi-diag` again.
- [ ] Confirm whether the stack-corruption fault is really gone or merely not
      triggered — the 16 KB stack fix is archived, not applied, so a panic can
      still return once association starts working.
- [ ] Remove `S41wifi-diag` and the `kernel.printk` raise once Wi-Fi is up.
- [ ] Board-specific values still unknown and deliberately not invented:
      Wi-Fi power-enable GPIO (if the MT7601 needs one), sensor/IR-cut/majestic
      pins, `gm8135s_lite.list` excludes trimming for 16 MB.
- [ ] Rotate the leaked Wi-Fi password; it is also in the image's U-Boot
      environment and in `BackupNowhereBeewiBC7PW.bin`.
- [ ] Persistence: the overlay upper is tmpfs because there is no `rootfs_data`
      partition; making it persistent needs a kernel MTD partition-map change.
- [ ] Optional: a script that replays the boot-region merge + env patches so the
      image can be regenerated from the vendor backup.
- [ ] The earlier request for an 8 MB image was superseded by the 16 MB one.

---

## 8. Build / reproduction

```sh
# stage the device profile into the build tree and build
make BOARD=gm8135s_lite_beewi-bc7pw

# outputs
openipc/output/images/uImage.gm8135s
openipc/output/images/rootfs.squashfs.gm8135s
```

Notes / gotchas seen while iterating:

- `all-patches/<package>/` patches only that package; kernel patches must live in
  `all-patches/linux/`. A patch dropped into the wrong directory is silently
  ineffective.
- Buildroot only re-extracts/re-patches a package when the patch set changes, so
  a new patch may appear to "not apply" against an existing build directory;
  remove `openipc/output/build/<pkg>` to force it. (The current build tree has
  `output/build/linux-custom` removed so the next build re-extracts and applies
  all three kernel patches exactly as CI would.)
- Non-UTF-8 bytes in the driver sources break naive Python patch generation;
  regenerate byte-safely against a pristine checkout and verify with
  `patch -p1 --dry-run` and `git apply --check`.
- `-fstack-protector-all` cannot be used in `arch/arm/boot/compressed` (undefined
  `__stack_chk_fail`/`__stack_chk_guard`); it needs `-fno-stack-protector` there.
- Removing `-DP2P_SUPPORT`/`-DAPCLI_SUPPORT` from the driver's top-level
  `Makefile:141` does **not** build: `rt_profile.c:651` references
  `pAd->ProbeRespIE` unconditionally, which those defines remove. The P2P code is
  enabled by `Makefile:141`, not by `os/linux/config.mk`, so config.mk edits have
  no effect on this build.
