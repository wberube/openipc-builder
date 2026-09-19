################################################################################
#
# wpa_supplicant-openipc
#
################################################################################

# 2.7 is the version that completes the WPA2-PSK handshake with the RDA5995
# FullMAC (rdawfmac) this board uses; see Config.in for what newer versions do
# instead.  The patches in 2.7/ are the ones this build needs; the package
# directory is deliberately free of the mbedtls/2.10-era patches the firmware
# tree ships next to it, and Buildroot's patch step applies the version
# subdirectory's patches instead of the package directory's when one exists.
WPA_SUPPLICANT_OPENIPC_VERSION = 2.7
WPA_SUPPLICANT_OPENIPC_SITE = https://w1.fi/releases
WPA_SUPPLICANT_OPENIPC_SOURCE = wpa_supplicant-$(WPA_SUPPLICANT_OPENIPC_VERSION).tar.gz
WPA_SUPPLICANT_OPENIPC_LICENSE = BSD-3-Clause
WPA_SUPPLICANT_OPENIPC_LICENSE_FILES = README
WPA_SUPPLICANT_OPENIPC_CPE_ID_VENDOR = w1.fi
WPA_SUPPLICANT_OPENIPC_CPE_ID_PRODUCT = wpa_supplicant
WPA_SUPPLICANT_OPENIPC_DEPENDENCIES = host-pkgconf libnl
WPA_SUPPLICANT_OPENIPC_SUBDIR = wpa_supplicant
WPA_SUPPLICANT_OPENIPC_CONFIG = $(@D)/$(WPA_SUPPLICANT_OPENIPC_SUBDIR)/.config
WPA_SUPPLICANT_OPENIPC_CFLAGS = $(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/libnl3/

# The configuration the unpatched Buildroot wpa_supplicant package produces for
# a station-only camera, reproduced here so the binary matches the one this
# board was verified with.  The options not present in the 2.7 defconfig are
# appended by the loop in the configure step.
WPA_SUPPLICANT_OPENIPC_CONFIG_ENABLE = \
	CONFIG_INTERNAL_LIBTOMMATH \
	CONFIG_MATCH_IFACE \
	CONFIG_LIBNL32

WPA_SUPPLICANT_OPENIPC_CONFIG_DISABLE = \
	CONFIG_SMARTCARD \
	CONFIG_DRIVER_WEXT \
	CONFIG_IBSS_RSN \
	CONFIG_EAP \
	CONFIG_IEEE8021X_EAPOL \
	CONFIG_FILS \
	CONFIG_DRIVER_WIRED \
	CONFIG_MACSEC \
	CONFIG_DRIVER_MACSEC_LINUX \
	CONFIG_HS20 \
	CONFIG_INTERWORKING \
	CONFIG_AP \
	CONFIG_P2P \
	CONFIG_WIFI_DISPLAY \
	CONFIG_MESH \
	CONFIG_HT_OVERRIDES \
	CONFIG_VHT_OVERRIDES \
	CONFIG_HE_OVERRIDES \
	CONFIG_WPS \
	CONFIG_DPP \
	CONFIG_SAE \
	CONFIG_SAE_PK \
	CONFIG_OWE \
	CONFIG_CTRL_IFACE_DBUS_NEW \
	CONFIG_DEBUG_SYSLOG \
	CONFIG_EAP_PWD \
	CONFIG_EAP_TEAP

# There is no openssl on this image: keep the internal crypto backend, which is
# what the verified binary was built with.
WPA_SUPPLICANT_OPENIPC_CONFIG_EDITS = 's/\#\(CONFIG_TLS=\).*/\1internal/'

define WPA_SUPPLICANT_OPENIPC_CONFIGURE_CMDS
	cp $(@D)/wpa_supplicant/defconfig $(WPA_SUPPLICANT_OPENIPC_CONFIG)
	sed -i $(patsubst %,-e 's/^#\(%\)/\1/',$(WPA_SUPPLICANT_OPENIPC_CONFIG_ENABLE)) \
		$(patsubst %,-e 's/^\(%\)/#\1/',$(WPA_SUPPLICANT_OPENIPC_CONFIG_DISABLE)) \
		$(patsubst %,-e %,$(WPA_SUPPLICANT_OPENIPC_CONFIG_EDITS)) \
		$(WPA_SUPPLICANT_OPENIPC_CONFIG)
	# options not listed in the upstream defconfig
	for s in $(WPA_SUPPLICANT_OPENIPC_CONFIG_ENABLE) ; do \
		if ! grep -q "^$${s}" $(WPA_SUPPLICANT_OPENIPC_CONFIG); then \
			echo "$${s}=y" >> $(WPA_SUPPLICANT_OPENIPC_CONFIG) ; \
		fi \
	done
endef

# LIBS for wpa_supplicant, LIBS_c for wpa_cli, LIBS_p for wpa_passphrase
define WPA_SUPPLICANT_OPENIPC_BUILD_CMDS
	$(TARGET_MAKE_ENV) CFLAGS="$(WPA_SUPPLICANT_OPENIPC_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" BINDIR=/usr/sbin \
		LIBS="$(WPA_SUPPLICANT_OPENIPC_LIBS)" LIBS_c="$(WPA_SUPPLICANT_OPENIPC_LIBS)" \
		LIBS_p="$(WPA_SUPPLICANT_OPENIPC_LIBS)" \
		$(MAKE) CC="$(TARGET_CC)" -C $(@D)/$(WPA_SUPPLICANT_OPENIPC_SUBDIR)
endef

ifeq ($(BR2_PACKAGE_WPA_SUPPLICANT_OPENIPC_CLI),y)
define WPA_SUPPLICANT_OPENIPC_INSTALL_CLI
	$(INSTALL) -m 0755 -D $(@D)/$(WPA_SUPPLICANT_OPENIPC_SUBDIR)/wpa_cli \
		$(TARGET_DIR)/usr/sbin/wpa_cli
endef
endif

ifeq ($(BR2_PACKAGE_WPA_SUPPLICANT_OPENIPC_PASSPHRASE),y)
define WPA_SUPPLICANT_OPENIPC_INSTALL_PASSPHRASE
	$(INSTALL) -m 0755 -D $(@D)/$(WPA_SUPPLICANT_OPENIPC_SUBDIR)/wpa_passphrase \
		$(TARGET_DIR)/usr/sbin/wpa_passphrase
endef
endif

# wpa_supplicant.conf is the Buildroot file with ctrl_interface enabled, i.e.
# the one the unpatched package installs on a station with the control
# interface turned on.
define WPA_SUPPLICANT_OPENIPC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/$(WPA_SUPPLICANT_OPENIPC_SUBDIR)/wpa_supplicant \
		$(TARGET_DIR)/usr/sbin/wpa_supplicant
	$(INSTALL) -m 0644 -D $(WPA_SUPPLICANT_OPENIPC_PKGDIR)/wpa_supplicant.conf \
		$(TARGET_DIR)/etc/wpa_supplicant.conf
	$(WPA_SUPPLICANT_OPENIPC_INSTALL_CLI)
	$(WPA_SUPPLICANT_OPENIPC_INSTALL_PASSPHRASE)
endef

$(eval $(generic-package))
