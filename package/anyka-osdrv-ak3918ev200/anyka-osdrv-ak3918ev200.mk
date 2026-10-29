################################################################################
#
# anyka-osdrv-ak3918ev200
#
################################################################################

ANYKA_OSDRV_AK3918EV200_VERSION =
ANYKA_OSDRV_AK3918EV200_SITE =
ANYKA_OSDRV_AK3918EV200_LICENSE = PROPRIETARY

# The SC1245, ISP2, VENC and ALSA drivers are built into the OpenIPC
# 4.4.302 kernel (CONFIG_SENSOR_SC1245, CONFIG_AK_ISP_CORE,
# CONFIG_VIDEO_AK_VENC, CONFIG_SND_AK_PCM). This package ships only the
# vendor userspace SDK libraries and the SC1245 ISP configuration.

define ANYKA_OSDRV_AK3918EV200_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/lib \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/lib/libplat_ai.so \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/lib/libplat_common.so \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/lib/libplat_drv.so \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/lib/libplat_ipcsrv.so \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/lib/libplat_thread.so \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/lib/libakuio.so
	for f in $(TARGET_DIR)/usr/lib/libak*.so; do \
		$(TARGET_STRIP) --strip-unneeded $$f; \
	done

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensors
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensors \
		$(ANYKA_OSDRV_AK3918EV200_PKGDIR)/files/etc/sensors/*.conf

	# The vendor libraries were built against uClibc and ask for
	# libc.so.0/libm.so.0/libpthread.so.0/libdl.so.0 by name. The image
	# is musl; expose those names to the single musl libc so they can be
	# dlopen()ed from /tmp.
	ln -sf libc.so $(TARGET_DIR)/lib/libc.so.0
	ln -sf libc.so $(TARGET_DIR)/lib/libm.so.0
	ln -sf libc.so $(TARGET_DIR)/lib/libpthread.so.0
	ln -sf libc.so $(TARGET_DIR)/lib/libdl.so.0
endef

$(eval $(generic-package))
