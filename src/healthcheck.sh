#! /bin/sh

set -e

if [ -f /backup_completion_time.log ]; then
    current_time=$(date +%s)
    backup_time=$(date --file /backup_completion_time.log +%s)
    age_in_seconds=$((current_time - backup_time))
    
    if [ ${age_in_seconds} -lt ${MAX_BACKUP_AGE_SECONDS} ]; then
        echo "Backup completed within the last ${MAX_BACKUP_AGE_SECONDS} seconds. Healthcheck passed."
        exit 0
    fi
fi

echo "Backup not completed within the last ${MAX_BACKUP_AGE_SECONDS} seconds. Healthcheck failed."
exit 1
