#!/bin/bash

# Preserve the wrapper's failure through the logging pipeline and stop the loop.
set -eo pipefail

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
    # The wrapper checks every repository after backups, using SLEEP_TIME as
    # its total check budget. Start the next cycle as soon as checks finish.
    /src/backup-wrapper.sh 2>&1 | log_message
done
