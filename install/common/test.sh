#!/bin/sh
# Off-car test of install/common/lib.sh (the boot hook) against a fake root.
# UNIT_SH: the shell to run it with (an ARM busybox ash is closest to the unit's mksh).
set -e
cd "$(dirname "$0")"
SH=${UNIT_SH:-sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: wanted [$2], got [$3]"; fail=1; fi; }
L() { env ROOT="$T" $SH -c ". $PWD/lib.sh; $*"; }
mkdir -p "$T/system/etc"
printf '#!/system/bin/sh\n# NEMESIS\nnemesis watchdog\nexit 0\n' > "$T/system/etc/install-recovery.sh"; chmod 755 "$T/system/etc/install-recovery.sh"
printf 'echo qb stock\n# NEMESIS_QB_HOOK\nnemesis watchdog\n' > "$T/system/etc/qb_runtime.sh"
IR=$(md5sum < "$T/system/etc/install-recovery.sh"); QB=$(md5sum < "$T/system/etc/qb_runtime.sh")

L hook_add /system/etc/install-recovery.sh top
check "block after the first line" "# HMGAPI_HOOK begin (HMG-API: starts hmgapid. HMG-API's uninstall removes this block.)" "$(sed -n 2p "$T/system/etc/install-recovery.sh")"
check "still ends with exit 0" "exit 0" "$(tail -1 "$T/system/etc/install-recovery.sh")"
check "NEMESIS lines kept" "1" "$(grep -c 'nemesis watchdog' "$T/system/etc/install-recovery.sh")"
check "stays executable" "yes" "$([ -x "$T/system/etc/install-recovery.sh" ] && echo yes)"
L hook_add /system/etc/install-recovery.sh top
check "adding twice keeps one block" "1" "$(grep -c 'HMGAPI_HOOK begin' "$T/system/etc/install-recovery.sh")"
L hook_add /system/etc/qb_runtime.sh end
check "qb block at the end" "# HMGAPI_HOOK end" "$(tail -1 "$T/system/etc/qb_runtime.sh")"
check "qb not made executable" "no" "$([ -x "$T/system/etc/qb_runtime.sh" ] && echo yes || echo no)"
sh -n "$T/system/etc/install-recovery.sh" && echo "ok    hooked script parses" || { echo "FAIL  hooked script syntax"; fail=1; }

L hook_remove /system/etc/install-recovery.sh
L hook_remove /system/etc/qb_runtime.sh
check "install-recovery.sh back byte for byte" "$IR" "$(md5sum < "$T/system/etc/install-recovery.sh")"
check "qb_runtime.sh back byte for byte" "$QB" "$(md5sum < "$T/system/etc/qb_runtime.sh")"

rm "$T/system/etc/install-recovery.sh"
L hook_add /system/etc/install-recovery.sh top
check "created when missing" "yes" "$([ -x "$T/system/etc/install-recovery.sh" ] && grep -q HMGAPI_CREATED "$T/system/etc/install-recovery.sh" && echo yes)"
L hook_remove /system/etc/install-recovery.sh
check "created file removed again" "no" "$([ -e "$T/system/etc/install-recovery.sh" ] && echo yes || echo no)"

# hook-check.sh at boot: a NEMESIS install or update rewrites install-recovery.sh as a whole
D=$T/data/hmgapi
mkdir -p "$D"; cp lib.sh "$D/"; echo "version 1.0.0" > "$D/installed.txt"
HC() { env ROOT="$T" $SH "$PWD/hook-check.sh" 2>&1; }
printf '#!/system/bin/sh\n# NEMESIS\nnemesis watchdog\nexit 0\n' > "$T/system/etc/install-recovery.sh"; chmod 755 "$T/system/etc/install-recovery.sh"
L hook_add /system/etc/install-recovery.sh top
L hook_add /system/etc/qb_runtime.sh end
IRH=$(md5sum < "$T/system/etc/install-recovery.sh"); QBH=$(md5sum < "$T/system/etc/qb_runtime.sh")
o=$(HC)
check "hook-check: both hooks there: nothing changed, nothing said" "|$IRH|$QBH" "$o|$(md5sum < "$T/system/etc/install-recovery.sh")|$(md5sum < "$T/system/etc/qb_runtime.sh")"
printf '#!/system/bin/sh\n# NEMESIS\nnemesis watchdog\nexit 0\n' > "$T/system/etc/install-recovery.sh"   # what a NEMESIS update writes
o=$(HC)
check "hook-check: install-recovery.sh rewritten: the block put back after the first line" "# HMGAPI_HOOK begin (HMG-API: starts hmgapid. HMG-API's uninstall removes this block.)" "$(sed -n 2p "$T/system/etc/install-recovery.sh")"
check "... as HMG-API's install puts it (same bytes)" "$IRH" "$(md5sum < "$T/system/etc/install-recovery.sh")"
check "... qb_runtime.sh left alone" "$QBH" "$(md5sum < "$T/system/etc/qb_runtime.sh")"
check "... said in install.log" "1" "$(grep -c 'boot hook put back in /system/etc/install-recovery.sh' "$D/install.log")"
check "... no lock left" "no" "$([ -e "$D/state/hook-check.pid" ] && echo yes || echo no)"
L hook_remove /system/etc/qb_runtime.sh
HC > /dev/null
check "hook-check: qb_runtime.sh lost it: put back at the end" "$QBH" "$(md5sum < "$T/system/etc/qb_runtime.sh")"
printf '#!/system/bin/sh\n# NEMESIS\nnemesis watchdog\nexit 0\n' > "$T/system/etc/install-recovery.sh"
rm "$D/installed.txt"
HC > /dev/null
check "hook-check: HMG-API not installed: nothing put back" "0" "$(grep -c HMGAPI_HOOK "$T/system/etc/install-recovery.sh")"
echo "version 1.0.0" > "$D/installed.txt"
cp "$(command -v sleep)" "$T/hook-check"; "$T/hook-check" 30 & sp=$!   # stands in for one already running
echo $sp > "$D/state/hook-check.pid"
HC > /dev/null
check "hook-check: another one running: this one does nothing" "0" "$(grep -c HMGAPI_HOOK "$T/system/etc/install-recovery.sh")"
kill $sp 2>/dev/null; wait $sp 2>/dev/null || true
echo 999999 > "$D/state/hook-check.pid"
HC > /dev/null
check "hook-check: a stale lock (after a restart) doesn't stop it" "1" "$(grep -c 'HMGAPI_HOOK begin' "$T/system/etc/install-recovery.sh")"

# wifi-probe.sh at boot: a chip nobody turned on (Korean units have no Wi-Fi switch) only
# shows on SDIO while Wi-Fi is on. Stand-ins: svc (Wi-Fi on sets wifi_on and brings the chip
# up if FAKE_CHIP; FAKE_REFUSE: nothing happens), settings (wifi_on), getprop (Android up),
# sleep (instant; FAKE_LATE: the chip shows up meanwhile); calls go to wifi.log.
B=$T/wbin; mkdir -p "$B" "$D/public" "$D/state" "$T/system/wifi" "$T/sys/bus/sdio/devices" "$T/system/etc/permissions"
S=$T/sys/bus/sdio/devices/mmc1:0001:1
cat > "$B/svc" <<EOS
#!/bin/sh
echo "svc \$*" >> "$T/wifi.log"
[ -n "\$FAKE_REFUSE" ] && exit 0
if [ "\$2" = enable ]; then echo 1 > "$T/wifi_on"; [ -n "\$FAKE_CHIP" ] && mkdir -p "$S"; fi
if [ "\$2" = disable ]; then echo 0 > "$T/wifi_on"; rm -rf "$S"; fi
exit 0
EOS
printf '#!/bin/sh\ncat "%s/wifi_on" 2>/dev/null || echo 0\n' "$T" > "$B/settings"
printf '#!/bin/sh\necho 1\n' > "$B/getprop"
printf '#!/bin/sh\n[ -n "$FAKE_LATE" ] && mkdir -p "%s"\nexit 0\n' "$S" > "$B/sleep"
chmod +x "$B"/*
WP() { env PATH="$B:$PATH" ROOT="$T" WIFI_PROBE_WAIT=0 $SH "$PWD/wifi-probe.sh" "$@" 2>&1; }
wlog() { cat "$T/wifi.log" 2>/dev/null | tr '\n' ';'; : > "$T/wifi.log"; }
yn() { [ -e "$1" ] && echo yes || echo no; }
reset() { rm -f "$D/public/wifi-chip" "$D/state/wifi-probe.txt" "$D/state/wifi-probe.on" "$D/state/wifi-probe.pid" "$D/install.log" "$T/wifi_on" "$T/system/etc/permissions/"*; rm -rf "$T/sys/bus/sdio/devices/"*; : > "$T/wifi.log"; }
reset
WP > /dev/null
check "wifi-probe: no driver in /system/wifi: not asked" "|no" "$(wlog)|$(yn "$D/public/wifi-chip")"
: > "$T/system/wifi/bcmdhd.ko"
(FAKE_CHIP=1; export FAKE_CHIP; WP > /dev/null)
check "wifi-probe: chip there, Wi-Fi off: on, then off again" "svc wifi enable;svc wifi disable;" "$(wlog)"
check "... remembered for SystemCheck (public/wifi-chip, readable by apps)" "-rw-r--r--" "$(ls -l "$D/public/wifi-chip" | cut -c1-10)"
check "... said in install.log" "1" "$(grep -c 'Wi-Fi chip found' "$D/install.log")"
check "... Wi-Fi and the chip off again, no marker or lock left" "0|no|no|no" "$(cat "$T/wifi_on")|$(yn "$S")|$(yn "$D/state/wifi-probe.on")|$(yn "$D/state/wifi-probe.pid")"
(FAKE_CHIP=1; export FAKE_CHIP; WP > /dev/null)
check "wifi-probe: known: not asked again" "" "$(wlog)"
reset
WP > /dev/null
check "wifi-probe: no chip: Wi-Fi on and off, nothing remembered" "svc wifi enable;svc wifi disable;|no" "$(wlog)|$(yn "$D/public/wifi-chip")"
check "... the answer kept and said" "none|1" "$(sed 's/.* //' "$D/state/wifi-probe.txt")|$(grep -c 'no Wi-Fi chip' "$D/install.log")"
WP > /dev/null
check "wifi-probe: asked once: not again at the next boot" "" "$(wlog)"
(FAKE_CHIP=1; export FAKE_CHIP; WP --again > /dev/null)
check "wifi-probe --again: asks again" "svc wifi enable;svc wifi disable;|yes" "$(wlog)|$(yn "$D/public/wifi-chip")"
reset
(FAKE_REFUSE=1; export FAKE_REFUSE; WP > /dev/null)
check "wifi-probe: Wi-Fi didn't come on: no answer kept, asked again next time" "no|1" "$(yn "$D/state/wifi-probe.txt")|$(grep -c "didn't come on" "$D/install.log")"
reset
echo 1 > "$T/wifi_on"
WP > /dev/null
check "wifi-probe: the owner has Wi-Fi on: left alone, no answer, no lock" "|no|no" "$(wlog)|$(yn "$D/state/wifi-probe.txt")|$(yn "$D/state/wifi-probe.pid")"
reset
printf '<permissions><feature name="com.hkmc.software.wifihotspot"/></permissions>\n' > "$T/system/etc/permissions/hotspot.xml"
(FAKE_CHIP=1; export FAKE_CHIP; WP > /dev/null)
check "wifi-probe: a car with the stock hotspot (SystemCheck counts its driver): not asked" "|no" "$(wlog)|$(yn "$D/state/wifi-probe.pid")"
reset
mkdir -p "$S"
WP > /dev/null
check "wifi-probe: chip already on SDIO: remembered, Wi-Fi not touched" "|yes" "$(wlog)|$(yn "$D/public/wifi-chip")"
reset
(FAKE_LATE=1; export FAKE_LATE; WP > /dev/null)
check "wifi-probe: chip turned on by something else while waiting: remembered, Wi-Fi not touched" "|yes" "$(wlog)|$(yn "$D/public/wifi-chip")"
reset
# cut off at power-off with Wi-Fi on: wifi_on stays 1, WifiService turns it on at the next boot
: > "$D/state/wifi-probe.on"; echo 1 > "$T/wifi_on"; mkdir -p "$S"
WP > /dev/null
check "wifi-probe: a run cut off with Wi-Fi on: turned off again, chip remembered" "svc wifi disable;|0|yes|no" "$(wlog)|$(cat "$T/wifi_on")|$(yn "$D/public/wifi-chip")|$(yn "$D/state/wifi-probe.on")"
check "... said in install.log" "1" "$(grep -c 'Wi-Fi turned off again' "$D/install.log")"
reset
echo $$ > "$D/state/wifi-probe.pid"   # a lock left by a process that's gone (or another pid)
(FAKE_CHIP=1; export FAKE_CHIP; WP > /dev/null)
check "wifi-probe: a stale lock doesn't stop it" "svc wifi enable;svc wifi disable;" "$(wlog)"
reset
rm "$D/installed.txt"
(FAKE_CHIP=1; export FAKE_CHIP; WP > /dev/null)
check "wifi-probe: HMG-API not installed: nothing" "" "$(wlog)"
echo "version 1.0.0" > "$D/installed.txt"
exit $fail
