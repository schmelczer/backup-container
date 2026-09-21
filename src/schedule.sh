#!/bin/bash

SLEEP_TIME=${SLEEP_TIME:-1h}

log_message() {
    stdbuf -o0 tee -a "$(get_log_file_name)"
}

get_log_file_name() {
    echo "/backup-logs/backup_$(date +%Y)_week_$(date +%U).log"
}

echo "Starting schedule script at $(date)" | log_message
mkdir -p /health || exit 1
trap 'rm -f /health/container_start_time.log.$$' EXIT
date -u '+%Y-%m-%dT%H:%M:%SZ' > /health/container_start_time.log.$$ &&
    mv -fT /health/container_start_time.log.$$ /health/container_start_time.log || exit 1

while true; do
    /src/backup-wrapper.sh 2>&1 | log_message
    echo "Sleeping for $SLEEP_TIME" | log_message

    # Using a simple sleep loop to schedule backups instead of cron to avoid concurrency issues
    sleep "$SLEEP_TIME"
done
