#!/bin/sh
#
# Perform basic settings on a known IP camera
#
#
# Set sensor type
#
fw_setenv sensor ov9732
#
#
# Set custom upgrade url
#
fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/gm8135_lite_wansview-ncm700gc-nor.tgz'
#
#
# Set wlan device and credentials if need
#
fw_setenv wlandev mt7601sta-generic
#fw_setenv wlanssid Router
#fw_setenv wlanpass 12345678

exit 0
