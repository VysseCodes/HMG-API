#!/bin/sh
# Off-car test on the patch engine: the driver goes in over the expected stock file only,
# the service is planned, and removing the mod gives the stock bytes back.
set -e
cd "$(dirname "$0")/../.."
CP=$(mktemp -d); T=$(mktemp -d); trap 'rm -rf "$T" "$CP"' EXIT
javac --release 8 -Xlint:-options -nowarn -d "$CP" core/runtime/java/hmgapi/engine/*.java 2>/dev/null
R=$T/root
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: wanted [$2], got [$3]"; fail=1; fi; }
has() { case "$3" in *"$2"*) echo "ok    $1" ;; *) echo "FAIL  $1: wanted [$2] in [$3]"; fail=1 ;; esac; }
eng() { set +e; out=$(HMGAPI_ROOT=$R HMGAPI_HOST=1 HMGAPI_TEST_ANY_CAR=1 HMGAPI_PRODUCT=SG2EV.USA.0000.V015.012.260507 HMGAPI_ONEBIN=sg2ev_us java -cp "$CP" hmgapi.engine.Engine "$@" 2>&1); rc=$?; set -e; }
sum() { python3 -c 'import hashlib,sys; print(hashlib.md5(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
mkdir -p $R/data/hmgapi/mods $R/data/hmgapi/settings $R/system/wifi
printf 'ro.board.platform=tcc803x\n' > $R/props.txt
: > $R/settings.txt
cp -r mods/usb-wifi-rtl8811au $R/data/hmgapi/mods/; rm $R/data/hmgapi/mods/usb-wifi-rtl8811au/test.sh
python3 - "$R/data/hmgapi/mods/usb-wifi-rtl8811au/mod.json" <<'P'
import json,sys
d=json.load(open(sys.argv[1])); d.pop("requires"); json.dump(d,open(sys.argv[1],"w"))
P
echo "not the expected stock driver" > $R/system/wifi/bcmdhd.ko
ORIG=$(sum $R/system/wifi/bcmdhd.ko)
eng apply; has "unknown stock driver refused" "$ORIG" "$out"
check "... and left alone" "$ORIG" "$(sum $R/system/wifi/bcmdhd.ko)"
python3 - "$R/data/hmgapi/settings/hmgapi.json" "$ORIG" <<'P'
import json,sys
json.dump({"overrides":{"accept_baseline":[{"path":"/system/wifi/bcmdhd.ko","md5":sys.argv[2]}]}},open(sys.argv[1],"w"))
P
eng plan; has "service planned" "usb-wifi-rtl8811au/usbguard as root, at boot" "$out"
eng apply; check "apply" 0 $rc
check "driver in place" "$(sum mods/usb-wifi-rtl8811au/files/bcmdhd-rtl8811au.ko)" "$(sum $R/system/wifi/bcmdhd.ko)"
eng restore; check "restore" 0 $rc
check "stock bytes back" "$ORIG" "$(sum $R/system/wifi/bcmdhd.ko)"
exit $fail
