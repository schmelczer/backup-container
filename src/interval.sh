#!/bin/bash

# Return whole seconds and a fractional part without floating-point rounding.
# Long multiplication keeps the range checks exact even for tiny fractions.
interval_duration() {
    local value=$1 whole fraction multiplier carry=0 product='' digit index
    if [[ ! $value =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)([smhd]?)$ ]]; then
        echo 'SLEEP_TIME must be a positive duration in seconds, minutes, hours or days.' >&2
        return 1
    fi
    case ${BASH_REMATCH[3]} in
        ''|s) multiplier=1 ;;
        m) multiplier=60 ;;
        h) multiplier=3600 ;;
        d) multiplier=86400 ;;
    esac
    value=${BASH_REMATCH[1]}
    whole=${value%%.*}
    whole=${whole#"${whole%%[!0]*}"}
    whole=${whole:-0}
    if (( ${#whole} > 10 )); then
        echo 'SLEEP_TIME must represent between 1 and 2147483647 seconds.' >&2
        return 1
    fi
    fraction=''
    [[ $value != *.* ]] || fraction=${value#*.}
    for ((index = ${#fraction} - 1; index >= 0; index--)); do
        digit=$((10#${fraction:index:1} * multiplier + carry))
        product="$((digit % 10))$product"
        carry=$((digit / 10))
    done
    whole=$((10#$whole * multiplier + carry))
    product=${product%"${product##*[!0]}"}
    if (( whole < 1 || whole > 2147483647 )) || { (( whole == 2147483647 )) && [[ -n $product ]]; }; then
        echo 'SLEEP_TIME must represent between 1 and 2147483647 seconds.' >&2
        return 1
    fi
    printf '%s %s\n' "$whole" "${product:-0}"
}

# /proc/uptime advances independently of wall-clock adjustments, in 10 ms ticks.
interval_now() {
    local uptime _idle whole fraction
    read -r uptime _idle < /proc/uptime || return 1
    whole=${uptime%.*}
    fraction=${uptime#*.}00
    printf '%s\n' "$((10#$whole * 100 + 10#${fraction:0:2}))"
}

interval_budget() {
    local duration
    duration=$(interval_duration "$1") || return 1
    printf '%s\n' "${duration%% *}"
}

interval_deadline() {
    local duration whole fraction ticks now
    duration=$(interval_duration "$1") || return 1
    read -r whole fraction <<< "$duration"
    fraction+='00'
    ticks=$((whole * 100 + 10#${fraction:0:2}))
    # Round up fractions and the current clock tick to preserve the minimum wait.
    [[ ${fraction:2} != *[1-9]* ]] || ticks=$((ticks + 1))
    now=$(interval_now) || return 1
    printf '%s\n' "$((now + ticks + 1))"
}

interval_wait() {
    local deadline=$1 now remaining delay
    [[ $deadline =~ ^[0-9]{1,15}$ ]] || return 1
    while true; do
        now=$(interval_now) || return 1
        remaining=$((10#$deadline - now))
        (( remaining > 0 )) || return 0
        printf -v delay '%d.%02d' "$((remaining / 100))" "$((remaining % 100))"
        sleep "$delay" || return 1
    done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        budget|deadline|wait)
            [[ $# == 2 ]] || exit 1
            "interval_$1" "$2"
            ;;
        *) echo 'Expected budget, deadline or wait and a value.' >&2; exit 1 ;;
    esac
fi
