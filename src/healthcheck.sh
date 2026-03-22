#! /bin/sh

set -e

MAX_BACKUP_AGE_SECONDS="${MAX_BACKUP_AGE_SECONDS:-86400}"

if [ -f /health/backup_completion_time.log ]; then
    current_time=$(date +%s)
    backup_time=$(date --file /health/backup_completion_time.log +%s)
    age_in_seconds=$((current_time - backup_time))

    if [ "${age_in_seconds}" -lt "${MAX_BACKUP_AGE_SECONDS}" ]; then
        echo "Backup completed within the last ${MAX_BACKUP_AGE_SECONDS} seconds. Healthcheck passed."
        exit 0
    fi
elif [ -f /health/container_start_time.log ]; then
    current_time=$(date +%s)
    start_time=$(date --file /health/container_start_time.log +%s)
    age_in_seconds=$((current_time - start_time))

    if [ "${age_in_seconds}" -lt "${MAX_BACKUP_AGE_SECONDS}" ]; then
        echo "No backup completed yet, but container started less than ${MAX_BACKUP_AGE_SECONDS} seconds ago. Healthcheck passed."
        exit 0
    fi
fi

echo "Backup not completed within the last ${MAX_BACKUP_AGE_SECONDS} seconds. Healthcheck failed."
exit 1
