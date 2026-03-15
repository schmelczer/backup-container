#!/bin/bash

KEEP_DAILY=${KEEP_DAILY:-6}
KEEP_WEEKLY=${KEEP_WEEKLY:-3}
KEEP_MONTHLY=${KEEP_MONTHLY:-48}
KEEP_YEARLY=${KEEP_YEARLY:-10}

echo "Starting backup script at $(date)"

export BORG_RSH='ssh -oBatchMode=yes' # https://borgbackup.readthedocs.io/en/stable/usage/notes.html#ssh-batch-mode

# break any stale locks in case the script was interrupted
borg break-lock

if ! borg info; then
    echo "Borg info returned a non-zero status. Initializing Borg..."
    borg init --encryption=repokey
fi

# The above command will fail if the repo hasn't been already initialized, 
# so we can ignore the return status. However, if any of the commands below fail,
# we want to stop the script immediately.
set -e

if [ -d "/snapshot/btrfs-root" ]; then
    btrfs subvolume delete /snapshot/btrfs-root
fi

btrfs subvolume snapshot /btrfs-root /snapshot

cd "/snapshot/btrfs-root$BACKUP_RELATIVE_PATH"

# Generate exclusions for git-untracked files if enabled
EXCLUDE_ARGS=(--exclude-from /exclude.conf)
if [ "${IGNORE_GIT_UNTRACKED:-false}" = "true" ]; then
    echo "Generating exclusions for git-untracked files..."
    GIT_EXCLUDE_FILE=$(mktemp)

    # Find all git repositories and list their untracked files
    find . -name .git -type d 2>/dev/null | while read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        (
            cd "$repo_dir"
            # Get untracked files (respecting .gitignore)
            git ls-files --others --exclude-standard 2>/dev/null | while read -r file; do
                # Output path relative to backup root
                echo "${repo_dir#./}/$file"
            done
        )
    done > "$GIT_EXCLUDE_FILE"

    excluded_count=$(wc -l < "$GIT_EXCLUDE_FILE")
    echo "Found $excluded_count git-untracked files to exclude"

    EXCLUDE_ARGS+=(--exclude-from "$GIT_EXCLUDE_FILE")
fi

borg create --stats \
    --list \
    --filter=AMCE \
    --files-cache=ctime,size,inode \
    --compression=zstd,12 \
    "${EXCLUDE_ARGS[@]}" ::"{hostname}-{now:%Y-%m-%dT%H:%M:%S}" .

# Clean up temporary exclude file
if [ -n "$GIT_EXCLUDE_FILE" ] && [ -f "$GIT_EXCLUDE_FILE" ]; then
    rm -f "$GIT_EXCLUDE_FILE"
fi

cd -

borg prune --list --stats \
    --keep-daily="$KEEP_DAILY" \
    --keep-weekly="$KEEP_WEEKLY" \
    --keep-monthly="$KEEP_MONTHLY" \
    --keep-yearly="$KEEP_YEARLY"

borg compact --threshold=5 --cleanup-commits --verbose --progress

btrfs subvolume delete /snapshot/btrfs-root

