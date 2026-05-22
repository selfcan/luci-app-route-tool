#!/bin/sh
# Storage Health Tool - eMMC Health Check
# Reads PRE_EOL/LIFE_A/LIFE_B from eMMC ext_csd register
# BusyBox compatible POSIX shell

SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" = "$0" ] && SCRIPT_DIR="."
. "$SCRIPT_DIR/storage_common.sh"

# Shared reader caches ext_csd and centralizes offsets so health/detail/analyze stay consistent.
EXT_CSD=$(rt_read_ext_csd 300)
MMC_CSD="$(cat "$RT_EXT_CSD_PATH_CACHE" 2>/dev/null)"
[ -n "$MMC_CSD" ] || MMC_CSD="cached_or_unknown"

if [ -z "$EXT_CSD" ]; then
    echo "eMMC_STATUS=未检测到eMMC设备"
    echo "EMMC_LIFE_TEXT=N/A"
    echo "EMMC_LIFE_LEFT_PCT=0"
    exit 1
fi

if [ ${#EXT_CSD} -lt 1000 ]; then
    echo "eMMC_STATUS=数据不完整"
    echo "EMMC_LIFE_TEXT=N/A"
    echo "EMMC_LIFE_LEFT_PCT=0"
    exit 1
fi

rt_parse_ext_csd_life "$EXT_CSD"
PRE_EOL_DEC="$RT_PRE_EOL_DEC"
SLC_DEC="$RT_LIFE_A_DEC"
MLC_DEC="$RT_LIFE_B_DEC"

MAIN_DEC="$SLC_DEC"; MAIN_TYPE="SLC/TYP_A"
if [ "$MLC_DEC" -gt "$MAIN_DEC" ]; then MAIN_DEC="$MLC_DEC"; MAIN_TYPE="MLC/TYP_B"; fi

if [ "$MAIN_DEC" -le 0 ]; then
    USED_PCT=0; LEFT_PCT=100; USED_RANGE="厂家未上报"
elif [ "$MAIN_DEC" -ge 11 ]; then
    USED_PCT=100; LEFT_PCT=0; USED_RANGE="超过100%"
else
    USED_PCT=$((MAIN_DEC * 10)); LEFT_PCT=$((100 - USED_PCT)); USED_RANGE="$(rt_life_used_text "$MAIN_DEC")"
fi

PRE_EOL_STR="$(rt_pre_eol_text "$PRE_EOL_DEC")"
STATUS="$(rt_status_by_used "$MAIN_DEC" "$PRE_EOL_DEC")"
LIFE_TEXT="约剩余${LEFT_PCT}%，按${MAIN_TYPE}较大磨损值估算；SLC:${SLC_DEC}($(rt_life_used_text "$SLC_DEC")) MLC:${MLC_DEC}($(rt_life_used_text "$MLC_DEC"))；预警:${PRE_EOL_STR}"

# Backward-compatible fields + corrected names.
echo "eMMC_STATUS=${STATUS}"
echo "eMMC_HEALTH=${LIFE_TEXT}"
echo "eMMC_EOL_PCT=${LEFT_PCT}"
echo "eMMC_EOL_DEC=${PRE_EOL_DEC}"
echo "eMMC_SLC_DEC=${SLC_DEC}"
echo "eMMC_MLC_DEC=${MLC_DEC}"
echo "eMMC_PATH=${MMC_CSD}"
echo "EMMC_PRE_EOL_DEC=${PRE_EOL_DEC}"
echo "EMMC_PRE_EOL_TEXT=${PRE_EOL_STR}"
echo "EMMC_LIFE_A_DEC=${SLC_DEC}"
echo "EMMC_LIFE_B_DEC=${MLC_DEC}"
echo "EMMC_PRE_EOL_HEX=${RT_PRE_EOL_HEX}"
echo "EMMC_LIFE_A_HEX=${RT_LIFE_A_HEX}"
echo "EMMC_LIFE_B_HEX=${RT_LIFE_B_HEX}"
echo "EMMC_EXT_CSD_OFFSETS=PRE_EOL:267,LIFE_A:268,LIFE_B:269"
echo "EMMC_LIFE_MAIN_TYPE=${MAIN_TYPE}"
echo "EMMC_LIFE_USED_BUCKET=${MAIN_DEC}"
echo "EMMC_LIFE_USED_PCT=${USED_PCT}"
echo "EMMC_LIFE_LEFT_PCT=${LEFT_PCT}"
echo "EMMC_LIFE_USED_RANGE=${USED_RANGE}"
echo "EMMC_LIFE_TEXT=${LIFE_TEXT}"
