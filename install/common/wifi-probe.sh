#!/system/bin/sh
# HMG-API: find out once whether this unit has a Wi-Fi chip. The chip only shows on
# SDIO while Wi-Fi or the hotspot is on, and a car whose software has no Wi-Fi
# switch (Korean units: wifi.module but no wifihotspot) never turns it on, so it
# looked like "no Wi-Fi chip" (seen on a Korean K5 Hybrid, 260902: BCM4359 there).
# Only on such a unit (no wifihotspot feature: elsewhere SystemCheck counts the driver),
# once Android is up, with the Broadcom driver in /system/wifi, nothing on SDIO and
# Wi-Fi off: Wi-Fi on for up to 20 s, then back off. A chip that answers writes
# public/wifi-chip (SystemCheck's hmgapi.wifi); the answer goes to state/wifi-probe.txt
# and install.log and it isn't asked again (--again: ask again). "none" is kept only if
# Wi-Fi really came on; otherwise the next boot asks again.
# state/wifi-probe.on is there while the probe has Wi-Fi on: a run cut off then (power
# off) leaves wifi_on=1, and the next run turns it off before anything else.
# Started by boot.sh and install.sh in the background. ROOT prefixes every path, for
# off-car tests only.
exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-   # hmgapid waits for its pipe to close: don't hold it
umask 077
ROOT=${ROOT:-}
D=$ROOT/data/hmgapi
SEEN=$D/public/wifi-chip
DONE=$D/state/wifi-probe.txt
ON=$D/state/wifi-probe.on
L=$D/state/wifi-probe.pid
LOG=$D/install.log
SDIO=$ROOT/sys/bus/sdio/devices
chip() { for d in "$SDIO"/*; do [ -e "$d" ] && return 0; done; return 1; }
seen() { : > "$SEEN" && chmod 644 "$SEEN"; }
booted() {   # wait for Android (an hour at most; the next boot tries again)
    n=0
    while [ "$(getprop sys.boot_completed)" != 1 ]; do
        sleep 5
        n=$((n + 1))
        [ $n -lt 720 ] || { rm -f "$L"; exit 1; }
    done
}
[ -f "$D/installed.txt" ] || exit 0
# another one running? (a stale pid after a restart may be any process, this one included)
if [ -f "$L" ]; then
    p=$(cat "$L")
    [ -n "$p" ] && [ "$p" != $$ ] && grep -q wifi-probe "/proc/$p/cmdline" 2>/dev/null && exit 0
fi
mkdir -p "$D/state" && echo $$ > "$L"
# a run cut off with Wi-Fi on: put it back off (the chip seen then is the answer)
if [ -f "$ON" ]; then
    booted
    sleep 5   # WifiService turns the saved wifi_on back on first
    chip && { seen; echo "$(date) chip" > "$DONE"; }
    svc wifi disable
    rm -f "$ON"
    echo "Wi-Fi turned off again (left on by a Wi-Fi chip check cut off at power-off)" >> "$LOG"
fi
[ "$1" = --again ] && rm -f "$DONE"
done_() { rm -f "$L"; exit 0; }
[ -f "$SEEN" ] || [ -f "$DONE" ] && done_
[ -f "$ROOT/system/wifi/bcmdhd.ko" ] || done_
grep -q com.hkmc.software.wifihotspot "$ROOT"/system/etc/permissions/*.xml 2>/dev/null && done_
chip && { seen; done_; }
booted
sleep ${WIFI_PROBE_WAIT:-30}   # after the launcher and the projection apps
# something turned the chip on meanwhile (the owner, a mod): that's the answer
chip && { seen; done_; }
case "$(settings get global wifi_on 2>/dev/null)" in 1|2) done_ ;; esac
: > "$ON"
svc wifi enable
i=0; found=
while [ $i -lt 20 ]; do
    sleep 1
    i=$((i + 1))
    chip && { found=1; break; }
done
came=$(settings get global wifi_on 2>/dev/null)
svc wifi disable
rm -f "$ON"
if [ -n "$found" ]; then
    seen
    echo "$(date) chip" > "$DONE"
    echo "Wi-Fi chip found (Wi-Fi turned on for ${i} s to look, then off again)" >> "$LOG"
elif [ "$came" = 1 ]; then
    echo "$(date) none" > "$DONE"
    echo "no Wi-Fi chip: Wi-Fi was on for 20 s and nothing answered on SDIO" >> "$LOG"
else
    echo "Wi-Fi chip check: Wi-Fi didn't come on (wifi_on=$came); asked again at the next restart" >> "$LOG"
fi
rm -f "$L"
