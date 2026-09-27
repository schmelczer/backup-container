#!/bin/bash

export BORG_RSH='ssh -oBatchMode=yes'

# Borg expands placeholders in both names and archive filters. Only the filter
# needs glob escaping; user-supplied prefixes are literal in both places.
borg_literal_prefix() {
    local mode=$1 prefix=$2 character index
    for ((index = 0; index < ${#prefix}; index++)); do
        character=${prefix:index:1}
        case "$character" in
            '{') printf '{{' ;;
            '}') printf '}}' ;;
            '['|'?'|'*')
                if [[ $mode == glob ]]; then
                    printf '[%s]' "$character"
                else
                    printf '%s' "$character"
                fi
                ;;
            *) printf '%s' "$character" ;;
        esac
    done
}

# Never break another client's repository/cache lock. Borg 1.4 only accepts
# finite waits, so retry lock timeouts forever; other errors must propagate.
borg_wait() {
    local status
    while true; do
        if BORG_EXIT_CODES=modern borg "$@" --lock-wait=60; then
            return 0
        else
            status=$?
        fi
        if (( status != 73 )); then
            return "$status"
        fi
        echo "Repository or cache is locked; continuing to wait..." >&2
    done
}
