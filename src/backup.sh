#!/bin/bash

set -e

: "${ARCHIVE_PREFIX:?Set ARCHIVE_PREFIX to a non-empty archive prefix (e.g. my-host-)}"

KEEP_DAILY=${KEEP_DAILY:-6}
KEEP_WEEKLY=${KEEP_WEEKLY:-3}
KEEP_MONTHLY=${KEEP_MONTHLY:-48}
KEEP_YEARLY=${KEEP_YEARLY:-10}

echo "Starting backup script at $(date)"

# shellcheck source=src/borg-common.sh
source /src/borg-common.sh

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
    if [ -n "${GIT_EXCLUDE_FILE:-}" ] && [ -f "$GIT_EXCLUDE_FILE" ]; then
        rm -f "$GIT_EXCLUDE_FILE"
    fi
    if [ -d "/snapshot/btrfs-root" ]; then
        cd /
        btrfs subvolume delete /snapshot/btrfs-root || true
    fi
}
trap cleanup EXIT

if [ -d "/snapshot/btrfs-root" ]; then
    btrfs subvolume delete /snapshot/btrfs-root
fi

btrfs subvolume snapshot /btrfs-root /snapshot

cd "/snapshot/btrfs-root${BACKUP_RELATIVE_PATH:-}"

# Generate exclusions for git-untracked files if enabled
EXCLUDE_ARGS=(--exclude-from /exclude.conf)
if [ "${IGNORE_GIT_UNTRACKED:-false}" = "true" ]; then
    echo "Generating exclusions for git-untracked files..."
    GIT_EXCLUDE_FILE=$(mktemp)

    # Find all git repositories and list their untracked files
    find . -name .git -type d | while read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        (
            cd "$repo_dir"
            # Get untracked files (respecting .gitignore)
            git ls-files --others --exclude-standard | while read -r file; do
                # Output path relative to backup root
                echo "${repo_dir#./}/$file"
            done
        )
    done > "$GIT_EXCLUDE_FILE"

    excluded_count=$(wc -l < "$GIT_EXCLUDE_FILE")
    echo "Found $excluded_count git-untracked files to exclude"

    EXCLUDE_ARGS+=(--exclude-from "$GIT_EXCLUDE_FILE")
fi

borg_wait create --stats \
    --list \
    --filter=AMCE \
    --files-cache=ctime,size,inode \
    --compression=zstd,12 \
    "${EXCLUDE_ARGS[@]}" ::"${ARCHIVE_PREFIX}{now:%Y-%m-%dT%H:%M:%S}" .

cd -

borg_wait prune --list --stats \
    --glob-archives="${ARCHIVE_PREFIX}*" \
    --keep-daily="$KEEP_DAILY" \
    --keep-weekly="$KEEP_WEEKLY" \
    --keep-monthly="$KEEP_MONTHLY" \
    --keep-yearly="$KEEP_YEARLY"

borg_wait compact --threshold=5 --cleanup-commits --verbose --progress
