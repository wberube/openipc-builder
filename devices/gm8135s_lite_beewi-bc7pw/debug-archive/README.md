# Archived diagnostics — mt7601sta stack corruption hunt

Instrumentation used to chase the wild write that smashed a kernel stack canary
in the vendor `mt7601sta` MLME task (`stack-protector: Kernel stack is corrupted
in: ...`, wild PC reached by an indirect call from `queue_work`). Kept here so
the hunt can be resumed, but **none of it is applied by the build**.

They were pulled because with them in place the camera no longer got past

    CPU: Testing write buffer coherency: ok

The vendor wireless module test needs none of them: the kernel is back to
`gm8135.generic.config` untouched, and the driver being exercised is the
vendor binary shipped in the overlay.

## What was archived

| file (mirrors original path) | what it did |
| --- | --- |
| `all-patches/linux/0001-arm-raise-kernel-stack-to-16k.patch` | `THREAD_SIZE_ORDER 1 -> 2`, 8K -> 16K stacks, to keep an overflow from reaching a canary |
| `all-patches/linux/0001-arm-stack-protector-all-diagnostic.patch` | `-fstack-protector-all` on the kernel (covers out-of-tree modules too) plus `-fno-stack-protector` in the decompressor, which has no canary support |
| `all-patches/linux/0002-report-canary-corruption-details.patch` | prints `guard= ret= sp=` and a 64-word frame dump before panicking |
| `gm8135-debug.fragment` | kernel config fragment: `CONFIG_CC_STACKPROTECTOR=y` (`CONFIG_DEBUG_SLAB` deliberately omitted — it misfires on this vendor SLAB from early boot) |
| `all-patches/mt7601u-openipc/0002-rt_os_util-disable-wext-assoc-ie-event.patch` | disabled the `RT_WLAN_EVENT_ASSOC_REQ_IE` WEXT notify; did not fix the fault, canary just moved |
| `all-patches/mt7601u-openipc/0003-assoc-bound-rsn-ie-copy.patch` | bounds check on the `RSN_IE` copy in `sta/assoc.c` (`RSN_IE` is 255 bytes, copy is `Len + 2`, so up to 257) |

`0001-mt7601sta-lower-cfg80211-beacon-version-guard.patch` was **not** archived:
it stays in `general/package/all-patches/mt7601u-openipc/` because the driver
package does not compile without it. GrainMedia backported the newer
`struct beacon_parameters` fields into this 3.3 tree, so the `(3, 4, 0)` guard
on `include/rtmp_cmd.h` is wrong here and `(3, 2, 0)` is right.

## Restoring them

```sh
cd devices/gm8135s_lite_beewi-bc7pw
mkdir -p general/package/all-patches/linux
cp debug-archive/all-patches/linux/*.patch general/package/all-patches/linux/
cp debug-archive/all-patches/mt7601u-openipc/*.patch general/package/all-patches/mt7601u-openipc/
mkdir -p br-ext-chip-grainmedia/board/gm8136
cp debug-archive/gm8135-debug.fragment br-ext-chip-grainmedia/board/gm8136/
```

Then add this line back to
`br-ext-chip-grainmedia/configs/gm8135s_lite_beewi-bc7pw_defconfig`, after
`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE`:

```
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(EXTERNAL_VENDOR)/board/$(OPENIPC_SOC_FAMILY)/gm8135-debug.fragment"
```

and force the kernel to be rebuilt — Buildroot does not always notice that a
patch disappeared from `BR2_GLOBAL_PATCH_DIR`:

```sh
rm -rf openipc/output/build/linux-custom
make BOARD=gm8135s_lite_beewi-bc7pw
```

Confirm it took: the built `mt7601sta.ko` should reference `__stack_chk_fail`
(only when the diagnostics are in) and
`openipc/output/build/linux-custom/.config` should show the fragment's options.
