#!/bin/bash

export BORG_RSH='ssh -oBatchMode=yes'

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
