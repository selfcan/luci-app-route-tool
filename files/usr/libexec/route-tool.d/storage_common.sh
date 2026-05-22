#!/bin/sh
# Shared helpers for Route Tool storage scripts.
# Keep this POSIX sh compatible: these files run under BusyBox ash on OpenWrt.

RT_COMMON_DIR=${0%/*}
[ "$RT_COMMON_DIR" = "$0" ] && RT_COMMON_DIR="."
RT_EXT_CSD_CACHE="${RT_EXT_CSD_CACHE:-/tmp/route-tool-ext-csd.cache}"
RT_EXT_CSD_PATH_CACHE="${RT_EXT_CSD_PATH_CACHE:-/tmp/route-tool-ext-csd.path}"
RT_EXT_CSD_CACHE_AGE="${RT_EXT_CSD_CACHE_AGE:-300}"

rt_hex2dec() {
    h="$(printf '%s' "$1" | tr 'A-F' 'a-f')"
    h="${h#0x}"
    case "$h" in
        ''|*[!0-9a-f]*) echo 0 ;;
        *) printf '%d\n' "0x$h" 2>/dev/null || echo 0 ;;
    esac
}

rt_cache_fresh() {
    file="$1"
    age="$2"
    [ -f "$file" ] || return 1
    cache_time="$(stat -c %Y "$file" 2>/dev/null || echo 0)"
    now="$(date +%s 2>/dev/null || echo 0)"
    case "$cache_time:$now:$age" in
        *[!0-9:]*|0:*) return 1 ;;
    esac
    [ $((now - cache_time)) -lt "$age" ]
}

rt_emmc_manf_name() {
    id="$(printf '%s' "$1" | tr 'A-F' 'a-f')"
    id="${id#0x}"
    # Single source of truth prevents the three previous manufacturer maps from drifting.
    # JEDEC/manufacturer ID 0x88 is Longsys(江波龙); keep this exact correction everywhere.
    case "$id" in
        01) echo "Samsung(三星)" ;;
        02) echo "SK Hynix(海力士)" ;;
        04) echo "Intel(英特尔)" ;;
        06) echo "Micron(美光)" ;;
        07) echo "Spansion/Cypress" ;;
        08) echo "Toshiba/Kioxia(东芝/铠侠)" ;;
        09) echo "STMicro" ;;
        0a) echo "GigaDevice(兆易创新)" ;;
        0b) echo "Macronix(旺宏)" ;;
        0c) echo "Winbond(华邦)" ;;
        15) echo "SanDisk(闪迪)" ;;
        19) echo "Western Digital(西部数据)" ;;
        20) echo "Lexar(雷克沙)" ;;
        25) echo "Kingston(金士顿)" ;;
        28) echo "Crucial(英睿达)" ;;
        29) echo "ADATA(威刚)" ;;
        2d) echo "YMTC(长江存储)" ;;
        2e) echo "CXMT(长鑫存储)" ;;
        30) echo "Netac(朗科)" ;;
        88|d6) echo "Longsys(江波龙)" ;;
        "") echo "未知" ;;
        *) echo "未知(0x$id)" ;;
    esac
}

rt_find_ext_csd_path() {
    for host in /sys/class/mmc_host/mmc*/mmc*:*/ext_csd; do
        [ -f "$host" ] && [ -r "$host" ] && { echo "$host"; return 0; }
    done
    for host in /sys/kernel/debug/mmc*/mmc*:*/ext_csd; do
        [ -f "$host" ] && [ -r "$host" ] && { echo "$host"; return 0; }
    done
    return 1
}

rt_read_ext_csd() {
    age="${1:-$RT_EXT_CSD_CACHE_AGE}"
    if rt_cache_fresh "$RT_EXT_CSD_CACHE" "$age"; then
        RT_EXT_CSD_PATH="$(cat "$RT_EXT_CSD_PATH_CACHE" 2>/dev/null)"
        cat "$RT_EXT_CSD_CACHE"
        return 0
    fi

    RT_EXT_CSD_PATH="$(rt_find_ext_csd_path 2>/dev/null)"
    if [ -z "$RT_EXT_CSD_PATH" ]; then
        # Mount debugfs once and cache the result so health/detail/analyze do not repeat the work.
        mount -t debugfs none /sys/kernel/debug 2>/dev/null
        RT_EXT_CSD_PATH="$(rt_find_ext_csd_path 2>/dev/null)"
    fi
    [ -n "$RT_EXT_CSD_PATH" ] || return 1

    raw="$(cat "$RT_EXT_CSD_PATH" 2>/dev/null | tr -d '\n ' | tr 'A-F' 'a-f')"
    [ ${#raw} -ge 1000 ] || return 1
    printf '%s\n' "$raw" > "$RT_EXT_CSD_CACHE" 2>/dev/null || true
    printf '%s\n' "$RT_EXT_CSD_PATH" > "$RT_EXT_CSD_PATH_CACHE" 2>/dev/null || true
    printf '%s\n' "$raw"
}

rt_ext_csd_byte_hex() {
    raw="$1"
    byte="$2"
    start=$((byte * 2 + 1))
    end=$((start + 1))
    printf '%s' "$raw" | cut -c"${start}-${end}"
}

rt_parse_ext_csd_life() {
    raw="$1"
    # The Linux/mmc-utils EXT_CSD indices are PRE_EOL_INFO=267,
    # DEVICE_LIFE_TIME_EST_TYP_A=268, DEVICE_LIFE_TIME_EST_TYP_B=269.
    # cut(1) positions are 1-based over the 1024-char hex string: byte*2+1..byte*2+2.
    RT_PRE_EOL_HEX="$(rt_ext_csd_byte_hex "$raw" 267)"
    RT_LIFE_A_HEX="$(rt_ext_csd_byte_hex "$raw" 268)"
    RT_LIFE_B_HEX="$(rt_ext_csd_byte_hex "$raw" 269)"
    RT_PRE_EOL_DEC="$(rt_hex2dec "$RT_PRE_EOL_HEX")"
    RT_LIFE_A_DEC="$(rt_hex2dec "$RT_LIFE_A_HEX")"
    RT_LIFE_B_DEC="$(rt_hex2dec "$RT_LIFE_B_HEX")"
}

rt_life_used_text() {
    case "$1" in
        0) echo "厂家未上报" ;;
        1) echo "0-10%" ;;
        2) echo "10-20%" ;;
        3) echo "20-30%" ;;
        4) echo "30-40%" ;;
        5) echo "40-50%" ;;
        6) echo "50-60%" ;;
        7) echo "60-70%" ;;
        8) echo "70-80%" ;;
        9) echo "80-90%" ;;
        10) echo "90-100%" ;;
        11) echo "超过100%" ;;
        *) echo "未知" ;;
    esac
}

rt_pre_eol_text() {
    case "$1" in
        0|1) echo "正常" ;;
        2) echo "接近寿命预警" ;;
        3) echo "已到寿命预警" ;;
        *) echo "未知" ;;
    esac
}

rt_status_by_used() {
    used="$1"
    pre="$2"
    if [ "$pre" -ge 3 ]; then echo "危险"; return; fi
    if [ "$pre" -eq 2 ]; then echo "警告"; return; fi
    if [ "$used" -le 3 ]; then
        echo "良好"
    elif [ "$used" -le 6 ]; then
        echo "一般"
    elif [ "$used" -le 8 ]; then
        echo "警告"
    else
        echo "严重"
    fi
}
