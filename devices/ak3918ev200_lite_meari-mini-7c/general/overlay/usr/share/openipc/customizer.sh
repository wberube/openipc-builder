#!/bin/sh
#
# Meari Mini 7C (AK3918EV200): first-boot settings.
#
fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/ak3918ev200_lite_meari-mini-7c-nor.tgz'
fw_setenv wlandev 8188fu

exit 0
