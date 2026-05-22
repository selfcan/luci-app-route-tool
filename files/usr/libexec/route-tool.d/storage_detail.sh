#!/bin/sh
# eMMC Detailed Information
# Reads CID register, identifies manufacturer, capacity, date

SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" = "$0" ] && SCRIPT_DIR="."
. "$SCRIPT_DIR/storage_common.sh"

CACHE_FILE="/tmp/storage_detail_cache"
CACHE_AGE=300

if rt_cache_fresh "$CACHE_FILE" "$CACHE_AGE"; then
    cat "$CACHE_FILE"
    exit 0
fi

# Find MMC device
MMC_DEV=""
for d in /sys/class/mmc_host/mmc*/mmc*:*; do
    if [ -d "$d" ]; then
        MMC_DEV="$d"
        break
    fi
done

if [ -z "$MMC_DEV" ]; then
    echo "DETAIL_ERR=未检测到eMMC设备"
    exit 1
fi

emit() { echo "$1"; }

{

if [ -f "${MMC_DEV}/cid" ]; then
    CID=$(cat "${MMC_DEV}/cid" 2>/dev/null)
else
    CID=""
fi

if [ -n "$CID" ] && [ ${#CID} -ge 16 ]; then
    MANFID=$(printf '%s' "$CID" | cut -c1-2)
    OEMID=$(printf '%s' "$CID" | cut -c3-4)
    PRDCT=$(printf '%s' "$CID" | cut -c5-10)
    SERIAL=$(printf '%s' "$CID" | cut -c15-22)
    DATE=$(printf '%s' "$CID" | cut -c23-26)
    MANF="$(rt_emmc_manf_name "$MANFID")"

    # Decode CID date with shared hex conversion; BusyBox awk may not provide strtonum().
    DATE_MONTH="$(rt_hex2dec "$(printf '%s' "$DATE" | cut -c1-1)")"
    DATE_YEAR_HEX="$(printf '%s' "$DATE" | cut -c2-4)"
    DATE_YEAR_OFFSET="$(rt_hex2dec "$DATE_YEAR_HEX")"
    DATE_YEAR=$((2000 + DATE_YEAR_OFFSET))
    case "$DATE_MONTH" in ''|*[!0-9]*) DATE_MONTH="?" ;; esac
    [ "$DATE_MONTH" -gt 12 ] 2>/dev/null && DATE_MONTH="?"

    emit "CID_RAW=${CID}"
    emit "MANUFACTURER_ID=0x${MANFID}"
    emit "MANUFACTURER=${MANF}"
    emit "OEM_ID=0x${OEMID}"
    emit "PRODUCT=${PRDCT}"
    emit "SERIAL=0x${SERIAL}"
    emit "MFG_DATE=${DATE_MONTH}/${DATE_YEAR}"
fi

# Block device capacity
# Resolve the block child from the MMC sysfs node so non-mmcblk0 eMMC devices are reported correctly.
BLK_BASE=""
for b in "$MMC_DEV"/block/mmcblk* /sys/block/mmcblk*; do
    [ -r "$b/size" ] || continue
    BLK_BASE="${b##*/}"
    break
done
[ -n "$BLK_BASE" ] || BLK_BASE="mmcblk0"
BLK_SIZE=$(cat "/sys/block/$BLK_BASE/size" 2>/dev/null || echo 0)
case "$BLK_SIZE" in ''|*[!0-9]*) BLK_SIZE=0 ;; esac
if [ "$BLK_SIZE" -gt 0 ]; then
    CAP_GB=$((BLK_SIZE * 512 / 1024 / 1024 / 1024))
    emit "CAPACITY_GB=${CAP_GB}"
    emit "SECTORS=${BLK_SIZE}"
fi

# Life time estimation from ext_csd
EXT_CSD="$(rt_read_ext_csd 300)"
if [ -n "$EXT_CSD" ]; then
    rt_parse_ext_csd_life "$EXT_CSD"
    emit "LIFE_EST_A=${RT_LIFE_A_DEC}"
    emit "LIFE_EST_B=${RT_LIFE_B_DEC}"
    emit "PRE_EOL=${RT_PRE_EOL_DEC}"
    emit "EMMC_FOUND=1"
    emit "EMMC_LIFE_A_HEX=${RT_LIFE_A_HEX}"
    emit "EMMC_LIFE_B_HEX=${RT_LIFE_B_HEX}"
    emit "EMMC_PRE_EOL_HEX=${RT_PRE_EOL_HEX}"
    emit "EMMC_EXT_CSD_OFFSETS=PRE_EOL:267,LIFE_A:268,LIFE_B:269"
fi

} | tee "$CACHE_FILE" 2>/dev/null
