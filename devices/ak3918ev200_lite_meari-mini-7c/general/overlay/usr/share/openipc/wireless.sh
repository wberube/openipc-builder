#!/bin/sh
#
# Local Wi-Fi credentials for this build. Not part of the branch; the
# firmware's S30customizer runs this once on first boot, before S40network.
#
dir=$(dirname "$0")
[ -f "$dir/wifi.local" ] || exit 0
. "$dir/wifi.local"

fw_setenv wlanssid "$WLANSSID"
fw_setenv wlanpass "$WLANPASS"
fw_setenv wlandev 8188fu
