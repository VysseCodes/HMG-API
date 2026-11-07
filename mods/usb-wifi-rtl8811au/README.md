# USB Wi-Fi for wireless CarPlay (RTL8811AU)

For a head unit where `wireless-carplay-aa` gets as far as the hotspot, but the built-in Wi-Fi
never comes up: `failed to power up DHD generic adapter`, nothing on `mmc1`, no `wlan0`.
It moves the hotspot to a USB adapter in the head unit's one USB port.

Tested on a 2023 Kia Niro EV (`SG2EV.USA`, firmware 260507) with a TP-Link Archer T2U Nano
(RTL8811AU, USB ID `2357:011e`) and an iPhone.

## Using it

1. Install this mod with `wireless-carplay-aa`, apply, and restart the head unit.
2. Turn ADB over USB off. The port only powers the adapter in host mode.
3. Plug in the adapter and connect the iPhone over Bluetooth. Don't plug in anything else: the
   port is shared, so wired CarPlay and USB drives need the adapter out.
4. Leave the manual hotspot toggle alone. It replaces the CarPlay network with the manual hotspot.
5. Pull the adapter before turning ADB back on. While the adapter is in, port power stays on.

## What it changes

- **`/system/wifi/bcmdhd.ko`**: the Realtek driver, under the Broadcom driver's name, so the stock
  Wi-Fi HAL loads and unloads it. Removing the mod restores the stock file.
- **`usbguard` service**: while the adapter is present, it sets the kernel's
  `vbus_control_enable` to 0, so the stock CarPlay app's `resetUSB()` can't cut power to the port.
  When the adapter is absent, it sets it to 1.

## The driver

`morrownr/8821au-20210708` with `tools/driver-changes.patch`. `tools/build-driver.sh` rebuilds
`files/bcmdhd-rtl8811au.ko` byte for byte from public sources. What the patch and build add:

- The module is named `bcmdhd` and takes the HAL's `iface_name`, `firmware_path`, `nvram_path` and
  `clm_path` parameters.
- `mac_address_read` in sysfs: the HAL reads it into `wifi.info.macaddress`.
- The stock hostapd's `add_ie` private command, which carries the Apple device IE. It's added to
  beacons, probe responses and association responses.
- The driver's own US channel plan. This kernel's `world_regdom` says 6 rules but lists 7, which
  drops channels 149-165, and there's no CRDA, so hostapd refused the hotspot's channel 149.

No source for the car's exact kernel is public. The module is built against a community 3.18.24
tree for the older TCC897x (`C457/android_kernel_telechips_tcc897x`). It was checked against the
car: every symbol it needs is exported, and 548 of the 549 kernel types shared with the stock
driver's debug info have the same layout (`linux_mib` differs, and this driver doesn't use it).
A build for other firmware needs the same checks, because a mismatch can crash the unit.

## WPA2 (a manual step)

On the test car the CarPlay network was set to WPA1 with TKIP. It was changed to WPA2 by editing
the auth type in `/data/misc/wifi/softap.conf` by hand (the int after the two SSIDs: 1 is
`WPA_PSK`, 4 is `WPA2_PSK`), then restarting. It wasn't tested whether CarPlay also works on WPA1.
This mod doesn't make that edit and removing it doesn't undo it, so keep a copy of the file.

## Known limits

- Only tested on one car, firmware and adapter, with sessions of up to 7.5 minutes. Long drives,
  cold starts, calls and audio quality aren't tested.
- `usbguard` hasn't blocked a real reset yet: in the session after its timing fix, CarPlay started
  before the stock app's timer ran out. If a reset gets through, the adapter comes back in about
  2.5 seconds and the phone rejoins.
- The car uses the mod's EV6 patch set, not one made for it.
