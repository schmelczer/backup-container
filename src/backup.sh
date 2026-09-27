#!/bin/bash

set -eo pipefail

: "${ARCHIVE_PREFIX:?Set ARCHIVE_PREFIX to a non-empty archive prefix (e.g. my-host-)}"

KEEP_DAILY=${KEEP_DAILY:-6}
KEEP_WEEKLY=${KEEP_WEEKLY:-3}
KEEP_MONTHLY=${KEEP_MONTHLY:-48}
KEEP_YEARLY=${KEEP_YEARLY:-10}

echo "Starting backup script at $(date)"

# shellcheck source=src/borg-common.sh
source /src/borg-common.sh
archive_prefix=$(borg_literal_prefix archive "$ARCHIVE_PREFIX")
archive_glob=$(borg_literal_prefix glob "$ARCHIVE_PREFIX")

# Only a missing repository (modern exit code 13) triggers initialization.
info_status=0
borg_wait info || info_status=$?
case "$info_status" in
    0) ;;
    13)
        echo "Repository does not exist. Initializing Borg..."
        init_status=0
        borg_wait init --encryption=repokey || init_status=$?
        case "$init_status" in
            0) ;;
            # Another client may have initialized the repository in between.
            10) borg_wait info ;;
            *) exit "$init_status" ;;
        esac
        ;;
    *)
        echo "Cannot access repository (Borg exit status $info_status). Skipping backup." >&2
        exit "$info_status"
        ;;
esac

cleanup() {
    local status=$?
    if [ -d "/snapshot/btrfs-root" ]; then
        cd /
        /src/snapshot.sh delete /snapshot/btrfs-root || status=1
    fi
    exit "$status"
}
trap cleanup EXIT

if [ -d "/snapshot/btrfs-root" ]; then
    /src/snapshot.sh delete /snapshot/btrfs-root
fi

/src/snapshot.sh create /btrfs-root /snapshot/btrfs-root

cd "/snapshot/btrfs-root${BACKUP_RELATIVE_PATH:-}"

borg_wait create --stats \
    --list \
    --filter=AMCE \
    --files-cache=ctime,size,inode \
    --compression=zstd,12 \
    --exclude-from /exclude.conf \
    ::"${archive_prefix}{now:%Y-%m-%dT%H:%M:%S}" .

cd -

borg_wait prune --list --stats \
    --glob-archives="${archive_glob}*" \
    --keep-daily="$KEEP_DAILY" \
    --keep-weekly="$KEEP_WEEKLY" \
    --keep-monthly="$KEEP_MONTHLY" \
    --keep-yearly="$KEEP_YEARLY"

borg_wait compact --threshold=5 --cleanup-commits --verbose --progress
