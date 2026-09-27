#!/bin/bash

echo "Starting backup wrapper script at $(date)"

mkdir -p /health || exit 1

# Called indirectly by the EXIT trap, including configuration failures.
# shellcheck disable=SC2317
finish() {
    local status=$?
    if (( status != 0 )); then
        touch /health/backup_failed || echo "Cannot record backup failure" >&2
    fi
    rm -f /health/backup_completion_time.log.$$
    exit "$status"
}
trap 'finish' EXIT

if [ -e /health/check_failed ]; then
    echo "A previous repository check failed. Investigate and run full checks before clearing /health/check_failed." >&2
    exit 1
fi

# shellcheck source=src/borg-common.sh
source /src/borg-common.sh || exit 1

execute_script() {
    echo "Executing $operation with:"
    if [ -n "$BORG_PASSPHRASE" ]; then
        echo "BORG_PASSPHRASE=<redacted>"
    fi
    echo "BORG_REMOTE_PATH='${BORG_REMOTE_PATH}'"
    echo "BORG_REPO='${BORG_REPO}'"

    local status=0
    if [[ $operation == backup ]]; then
        /src/backup.sh || status=$?
    else
        echo "Checking repository for up to $check_duration seconds"
        borg_wait check --repository-only --max-duration="$check_duration" --info || status=$?
        if (( status != 0 )); then
            # Later partial checks may skip the damaged segment. Only clear
            # this marker manually after investigating and fully checking it.
            touch /health/check_failed || status=1
            echo "Repository check failed (Borg exit status $status). Stopping backup cycle." >&2
            exit "$status"
        fi
    fi
    if (( status != 0 )); then
        # Report failure while later targets are still running, and keep it
        # across retries and container restarts until every target succeeds.
        touch /health/backup_failed || return 1
    fi
    return "$status"
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
    local check_budget check_duration check_deadline operation
    local index target_count=1 any_failed=false completed_indices indexed_var_name
    # Preserve the existing SLEEP_TIME setting, including fractional durations.
    check_budget=$(/src/interval.sh budget "${SLEEP_TIME:-1h}") || return 1

    # Finish every backup before spending the former sleep interval checking.
    for operation in backup check; do
        if [[ $operation == check ]]; then
            check_deadline=$(/src/interval.sh deadline "${SLEEP_TIME:-1h}") || return 1
        fi
        check_duration=$((check_budget / target_count))
        if (( check_duration == 0 )); then
            echo "SLEEP_TIME must allow at least one second per repository."
            return 1
        fi
        if [ -n "$BORG_REPO" ]; then
            execute_script || any_failed=true
        else
            index=0
            completed_indices=" "
            while configure_environment "$index"; do
                execute_script || any_failed=true
                completed_indices+="$index "
                unset BORG_PASSPHRASE BORG_REMOTE_PATH BORG_REPO
                ((index++))
            done
            target_count=$index

            if (( index == 0 )); then
                echo "No valid configuration found. Please ensure environment variables are set properly."
                return 1
            fi

            # A missing or incomplete target must not silently hide later targets.
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
        fi
    done

    if [[ $any_failed == true ]]; then
        echo "Skipping completion log due to backup or check failure(s)"
        return 1
    fi

    # Clear the failure only after publishing a complete, successful timestamp.
    date -u '+%Y-%m-%dT%H:%M:%SZ' > /health/backup_completion_time.log.$$ &&
        mv -fT /health/backup_completion_time.log.$$ /health/backup_completion_time.log &&
        rm -f /health/backup_failed || return 1

    # A partial check can finish early. Keep the configured interval between
    # backup rounds, counting checks and lock waits toward that interval.
    /src/interval.sh wait "$check_deadline"
}

main
backup_status=$?

echo "Finished backup wrapper script at $(date)"
exit "$backup_status"
