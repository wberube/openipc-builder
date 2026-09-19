#!/bin/sh
#
# Perform basic settings on a known IP camera
#
#
# Set custom upgrade url
#
fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/gk7102ca_lite_umea-qc01x-nor.tgz'
#
#
# Set custom majestic settings
#
# GPIO map recovered from the OEM firmware (/bak/hardinfo.bin, BoardType 1300,
# KAIZE eyeplus_ipc_gkc_006):
#   IrCut1B 17   IrCut2B 14   IrCtrl (IR LED) 23   WhiteLight 24
#   SpeakerCtrl 12   BoardReset 16   WifiCtrl 4   IrFeedback 0
#
cli -s .nightMode.irCutPin1 17
cli -s .nightMode.irCutPin2 14
# majestic drives a single illuminator pin. 23 is the IR LED and 24 the white
# floodlight; use 24 here instead if you want the visible light. There is no
# photocell (IrFeedback 0), so lightMonitor/lightSensorPin stay unset.
cli -s .nightMode.backlightPin 23
cli -s .audio.speakerPin 12
#cli -s .video0.codec h264
#
#
# Set wlan device and credentials if need
#
fw_setenv wlandev rda-generic
#fw_setenv wlanssid Router
#fw_setenv wlanpass 12345678
#
#
# Set ptz motor pins
# OEM /bak/ptz.cfg: motor_pins = 28,27,5,22,21,11,13,15
# (pan 28 27 5 22, tilt 21 11 13 15; swap the halves if the axes are crossed)
#
fw_setenv ptz_control gpio
fw_setenv ptz_gpio '28 27 5 22 21 11 13 15'
#
#
# reset gpio - 16
# wifi gpio - 4 (held by custom_init.sh in the OEM firmware)
#
exit 0
