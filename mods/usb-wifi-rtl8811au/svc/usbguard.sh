#!/system/bin/sh
# The stock CarPlay app power-cycles the USB port when a wired session doesn't start
# (resetUSB), which would drop the Wi-Fi adapter and the hotspot. While the adapter is
# on the port, keep the kernel's port power control off. Init also turns it on during
# boot, so check the actual value every second rather than only setting it once.
P=${USBGUARD_PARAM:-/sys/module/tcc_dwc_otg/parameters/vbus_control_enable}
V=${USBGUARD_VID:-2357}
D=${USBGUARD_PID:-011e}
while true; do
  want=1
  for d in /sys/bus/usb/devices/*; do
    if [ -f $d/idVendor ] && [ "$(cat $d/idVendor)" = "$V" ] && [ "$(cat $d/idProduct)" = "$D" ]; then want=0; fi
  done
  if [ "$(cat $P)" != "$want" ]; then
    echo $want > $P
    echo "$(date) adapter guard: vbus_control_enable=$want"
  fi
  sleep 1
done
