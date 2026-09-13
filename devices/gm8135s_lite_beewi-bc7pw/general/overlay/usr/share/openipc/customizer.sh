#!/bin/sh
#
# Perform basic settings on a known IP camera
#
#
# Set custom upgrade url
#
fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/gm8135s_lite_beewi-bc7pw-nor.tgz'
#
#
# Set custom majestic settings
#
cli -s .video0.codec h264
#
#
# Set wlan device and credentials if needed
#
fw_setenv wlandev mt7601sta-beewi-bc7pw
#
exit 0
