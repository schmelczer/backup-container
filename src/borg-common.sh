#!/bin/bash

export BORG_RSH='ssh -oBatchMode=yes'

borg_ensure_repository() {
    local status=0
    borg_wait info || status=$?
    (( status != 0 )) || return 0
    # Borg 1.4 reports InvalidRepository over SSH as generic RPC exit code 2,
    # even with modern exit codes enabled. Let init validate the destination:
    # it accepts missing/empty directories and refuses existing data.
    if (( status == 2 || status == 13 || status == 15 )); then
        echo 'Repository could not be opened. Attempting Borg initialization...'
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
# finite waits, so retry lock timeouts forever. Connection failures also retry
# indefinitely without recording a failed check; health expires independently.
borg_wait() {
    local status
    while true; do
        if BORG_EXIT_CODES=modern borg "$@" --lock-wait=60; then
            return 0
        else
            status=$?
        fi
        case $status in
            73)
                echo "Repository or cache is locked; continuing to wait..." >&2
                ;;
            80|81|87)
                echo "Remote connection failed (Borg exit status $status); retrying in 60 seconds..." >&2
                sleep 60 || return $?
                ;;
            *) return "$status" ;;
        esac
    done
}
