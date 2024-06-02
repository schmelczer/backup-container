#!/bin/bash

SLEEP_TIME=${SLEEP_TIME:-1h}

log_message() {
    stdbuf -o0 tee -a "$(get_log_file_name)"
}

get_log_file_name() {
    echo "/backup-logs/backup_$(date +%Y)_week_$(date +%U).log"
}

echo "Starting schedule script at `date`" | log_message

while true; do
    exec /src/backup-wrapper.sh 2>&1 | log_message
    echo "Sleeping for $SLEEP_TIME" | log_message

    # Using a simple sleep loop to schedule backups instead of cron to avoid concurrency issues
    sleep "$SLEEP_TIME"
done
