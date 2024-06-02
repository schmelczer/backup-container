#!/bin/bash

echo "Starting backup wrapper script at `date`"

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
    local index=$1
    local all_vars_set=true
    # required variables
    for var in BORG_PASSPHRASE BORG_REPO; do
        local indexed_var_name="${var}_${index}"
        if [[ -n "${!indexed_var_name}" ]]; then
            export $var="${!indexed_var_name}"
        else
            all_vars_set=false
            break
        fi
    done

    # optional variables
    for var in BORG_REMOTE_PATH; do
        local indexed_var_name="${var}_${index}"
        export $var="${!indexed_var_name}"
    done

    [[ $all_vars_set == true ]]
}

main() {
    if [ -n "$BORG_PASSPHRASE" ] && [ -n "$BORG_REPO" ]; then
        execute_script
    else
        local index=0
        local configurations_found=false

        while configure_environment $index; do
            execute_script || true
            configurations_found=true
            unset BORG_PASSPHRASE BORG_REMOTE_PATH BORG_REPO
            ((index++))
        done

        if [[ $configurations_found == false ]]; then
            echo "No valid configuration found. Please ensure environment variables are set properly."
        fi
    fi
}

main

echo "Finished backup wrapper script at `date`"
