# anyka-osdrv-ak3918ev200

Vendor userspace SDK libraries for the AK3918EV200, taken from the stock
rootfs. The kernel side is already built into the OpenIPC 4.4.302 kernel:
`CONFIG_SENSOR_SC1245`, `CONFIG_AK_ISP_CORE`, `CONFIG_VIDEO_AK_VENC` and
`CONFIG_SND_AK_PCM`. No `.ko` are installed.

Installed:

    /usr/lib/libakuio.so
    /usr/lib/libplat_ai.so
    /usr/lib/libplat_common.so
    /usr/lib/libplat_drv.so
    /usr/lib/libplat_ipcsrv.so
    /usr/lib/libplat_thread.so
    /etc/sensors/isp_sc1245.conf
    /etc/sensors/isp_1034_dvp_101602.conf
    /etc/sensors/isp_h62.conf

The libraries are uClibc-built (`NEEDED libc.so.0`, `libm.so.0`,
`libpthread.so.0`). The package adds those names as links to the musl
libc so they can be loaded on this image.

Run from `/tmp` (tmpfs, no flash writes):

    cp -a /usr/lib/libak*.so /tmp/
    cp -a /etc/sensors /tmp/
    LD_LIBRARY_PATH=/tmp your-app

The sensor and ISP kernel drivers are built-in; the vendor `home/anyka/*.ko`
and `loadanyka3918` from the dump are for the 3.4.35 vendor kernel and are
not installed.

## First login

The image keeps the firmware's claim gate: root's login shell is
`/usr/sbin/openipc-claim` until a password is set. dropbear is started with
`-B`, which allows an empty-password session, so `ssh root@<address>` reaches
the claim script and it asks for the new password. After that the shell is
`/bin/sh` again. The browser setup page belongs to majestic's web server,
which this profile does not install.
