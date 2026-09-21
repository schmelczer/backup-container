#!/bin/bash

echo "Starting backup wrapper script at $(date)"

execute_script() {
    echo "Executing script with:"
    if [ -n "$BORG_PASSPHRASE" ]; then
        echo "BORG_PASSPHRASE=<redacted>"
    fi
    echo "BORG_REMOTE_PATH='${BORG_REMOTE_PATH}'"
    echo "BORG_REPO='${BORG_REPO}'"

    /src/backup.sh
}

configure_environment() {
    local repo_var="BORG_REPO_$1" passphrase_var="BORG_PASSPHRASE_$1" remote_var="BORG_REMOTE_PATH_$1"
    [[ -n ${!repo_var} && -n ${!passphrase_var} ]] || return 1
    export BORG_REPO="${!repo_var}" BORG_PASSPHRASE="${!passphrase_var}"

    if [[ -n ${!remote_var} ]]; then
        export BORG_REMOTE_PATH="${!remote_var}"
    else
        unset BORG_REMOTE_PATH
    fi
}

main() {
    if [ -n "$BORG_REPO" ]; then
        # fallback case if multi-target backup isn't needed
        if ! execute_script; then
            echo "Skipping completion log due to backup failure"
            return 1
        fi
    else
        local index=0
        local any_failed=false
        local completed_indices=" "

        while configure_environment "$index"; do
            execute_script || any_failed=true
            completed_indices+="$index "
            unset BORG_PASSPHRASE BORG_REMOTE_PATH BORG_REPO
            ((index++))
        done

        echo "Finished backup script at $(date)"
        if (( index == 0 )); then
            echo "No valid configuration found. Please ensure environment variables are set properly."
            return 1
        fi

        # A missing or incomplete target must not silently hide later targets.
        local indexed_var_name
        for indexed_var_name in ${!BORG_REPO_@} ${!BORG_PASSPHRASE_@} ${!BORG_REMOTE_PATH_@}; do
            [[ -n ${!indexed_var_name} ]] || continue
            case "$completed_indices" in
                *" ${indexed_var_name##*_} "*) ;;
                *)
                    echo "Invalid or non-contiguous backup configuration: $indexed_var_name. Skipping completion log."
                    return 1
                    ;;
            esac
        done

        if [[ $any_failed == true ]]; then
            echo "Skipping completion log due to backup failure(s)"
            return 1
        fi
    fi

    # Rename only a complete timestamp, leaving the previous success intact on failure.
    mkdir -p /health || return 1
    trap 'rm -f /health/backup_completion_time.log.$$' EXIT
    date -u '+%Y-%m-%dT%H:%M:%SZ' > /health/backup_completion_time.log.$$ &&
        mv -fT /health/backup_completion_time.log.$$ /health/backup_completion_time.log
}

main
backup_status=$?

echo "Finished backup wrapper script at $(date)"
exit "$backup_status"
