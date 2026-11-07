#!/bin/sh
# Rebuilds files/bcmdhd-rtl8811au.ko in Docker (Ubuntu 16.04, gcc 4.9) from public sources.
#   mods/usb-wifi-rtl8811au/tools/build-driver.sh <output.ko>
# Kernel: a community 3.18.24 Telechips tree for the older TCC897x, not the car's exact source
# (Mobis hasn't published that). kernel.config is the car's config resolved against this tree.
set -e
OUT=${1:?usage: build-driver.sh <output.ko>}
cd "$(dirname "$0")"
KERNEL=3402d473aed6a2b82c5d08e0ceafc4a54701a4a0   # C457/android_kernel_telechips_tcc897x
DRIVER=1a819991f5b75e64dfcf922b96a6681f367cbba0   # morrownr/8821au-20210708
docker run --rm -i --platform linux/arm64 -e KERNEL=$KERNEL -e DRIVER=$DRIVER \
    -v "$PWD":/in:ro ubuntu:16.04 sh -es > "$OUT" <<'SCRIPT'
exec 3>&1 1>&2
apt-get update -qq
apt-get install -y -qq --no-install-recommends gcc-4.9-arm-linux-gnueabi binutils-arm-linux-gnueabi \
    make bc gcc libc6-dev python curl ca-certificates patch perl >/dev/null
ln -sf /usr/bin/arm-linux-gnueabi-gcc-4.9 /usr/bin/arm-linux-gnueabi-gcc
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-
mkdir -p /w/k /w/8821au-20210708
curl -sSL https://codeload.github.com/C457/android_kernel_telechips_tcc897x/tar.gz/$KERNEL | tar xz --strip-components=1 -C /w/k
curl -sSL https://codeload.github.com/morrownr/8821au-20210708/tar.gz/$DRIVER | tar xz --strip-components=1 -C /w/8821au-20210708
cd /w/k
# options the car's TCC803X build selects, which this tree's Kconfig would drop
printf '\nconfig CAR_ABI\n\tdef_bool y\n\tselect ARCH_DMA_ADDR_T_64BIT\n\tselect ZONE_DMA\n\tselect MIGHT_HAVE_PCI\n' >> arch/arm/Kconfig
# the car's kernel has the vmacache_seqnum u64 backport
sed -i 's/^\(\s*\)u32 vmacache_seqnum;/\1u64 vmacache_seqnum;/' include/linux/mm_types.h include/linux/sched.h
cp /in/kernel.config .config
make olddefconfig >/dev/null 2>&1
make -j6 modules_prepare >/dev/null 2>&1
cd /w/8821au-20210708
patch -p1 -s < /in/driver-changes.patch
make -j6 KSRC=/w/k CONFIG_PLATFORM_AUTODETECT=n CONFIG_RTW_ANDROID=4 CONFIG_LOAD_PHY_PARA_FROM_FILE=n \
    CONFIG_POWER_SAVING=n CONFIG_WIFI_MONITOR=n CONFIG_RTW_LOG_LEVEL=2 \
    KCFLAGS="-DCONFIG_RTW_REGD_SRC=0 -DCONFIG_APPEND_VENDOR_IE_ENABLE -DCONFIG_LITTLE_ENDIAN -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT" \
    modules >/dev/null 2>&1
arm-linux-gnueabi-strip --strip-debug -o /tmp/out.ko bcmdhd.ko
cat /tmp/out.ko >&3
SCRIPT
md5 -q "$OUT" 2>/dev/null || md5sum "$OUT"
