#!/bin/bash

KEEP_DAILY=${KEEP_DAILY:-6}
KEEP_WEEKLY=${KEEP_WEEKLY:-3}
KEEP_MONTHLY=${KEEP_MONTHLY:-48}
KEEP_YEARLY=${KEEP_YEARLY:-0}

echo "Starting backup script at `date`"

export BORG_RSH='ssh -oBatchMode=yes' # https://borgbackup.readthedocs.io/en/stable/usage/notes.html#ssh-batch-mode

# break any stale locks in case the script was interrupted
borg break-lock

borg info # test whether we have a valid repository
if [ $? -ne 0 ]; then
    echo "Borg info returned a non-zero status. Initializing Borg..."
    borg init --encryption=repokey
fi

# the above command will fail if the repo hasn't been already initialized, so we can ignore the return status
set -e

if [ -d "/snapshot/source" ]; then
    btrfs subvolume delete /snapshot/source
fi

btrfs subvolume snapshot /source /snapshot

cd /snapshot/source
borg create --stats --list --filter=AMCE --files-cache=ctime,size --compression=zstd,12 --exclude-from /exclude.conf ::"{hostname}-{now:%Y-%m-%dT%H:%M:%S}" .
cd -

borg prune --list --stats \
    --keep-daily=$KEEP_DAILY \
    --keep-weekly=$KEEP_WEEKLY \
    --keep-monthly=$KEEP_MONTHLY \
    --keep-yearly=$KEEP_YEARLY

borg compact --threshold=5 --cleanup-commits --verbose --progress

btrfs subvolume delete /snapshot/source

echo "Finished backup script at `date`"
