#! /bin/sh

set -e

MAX_BACKUP_AGE_SECONDS="${MAX_BACKUP_AGE_SECONDS:-86400}"

unhealthy() {
    echo "$* Healthcheck failed."
    exit 1
}

if ! [ "$MAX_BACKUP_AGE_SECONDS" -gt 0 ] 2>/dev/null; then
    unhealthy "MAX_BACKUP_AGE_SECONDS must be a positive integer."
fi

timestamp_file=/health/backup_completion_time.log
[ -f "$timestamp_file" ] || timestamp_file=/health/container_start_time.log

timestamp=$(cat "$timestamp_file") || unhealthy "Cannot read $timestamp_file."
case "$timestamp" in
    *[![:space:]]*) ;;
    *) unhealthy "Empty timestamp in $timestamp_file." ;;
esac
recorded_time=$(date --date="$timestamp" +%s 2>/dev/null) || unhealthy "Invalid timestamp in $timestamp_file."

# Read the clock after the marker, which may have just been replaced by a backup.
current_time=$(date +%s)
age_in_seconds=$((current_time - recorded_time))
if [ "$age_in_seconds" -ge 0 ] && [ "$age_in_seconds" -lt "$MAX_BACKUP_AGE_SECONDS" ]; then
    echo "Timestamp in $timestamp_file is ${age_in_seconds} seconds old. Healthcheck passed."
    exit 0
fi

unhealthy "Timestamp in $timestamp_file is outside the allowed age of ${MAX_BACKUP_AGE_SECONDS} seconds."
