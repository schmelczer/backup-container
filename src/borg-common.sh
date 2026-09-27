#!/bin/bash

export BORG_RSH='ssh -oBatchMode=yes'

borg_ensure_repository() {
    local status=0
    borg_wait info || status=$?
    (( status != 0 )) || return 0
    if (( status == 13 )) || (( status == 15 )); then
        echo 'Repository is missing or confirmed empty. Initializing Borg...'
        status=0
        borg_wait init --encryption=repokey || status=$?
        # Another client may have initialized it after the initial check.
        if (( status == 10 )); then
            borg_wait info
        else
            return "$status"
        fi
    else
        echo "Cannot access repository (Borg exit status $status). Skipping backup." >&2
        return "$status"
    fi
}

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
