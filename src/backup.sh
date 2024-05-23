#!/bin/bash

echo "Starting backup script at `date`"

export BORG_RSH='ssh -oBatchMode=yes' # https://borgbackup.readthedocs.io/en/stable/usage/notes.html#ssh-batch-mode

borg break-lock
borg info

if [ $? -ne 0 ]; then
    echo "Borg info returned a non-zero status. Initializing Borg..."
    borg init --encryption=repokey
fi

set -e

if [ -d "/snapshot/source" ]; then
    btrfs subvolume delete /snapshot/source
fi

btrfs subvolume snapshot /source /snapshot

cd /snapshot/source
borg create --stats --list --filter=AMCE --files-cache=ctime,size --compression=zstd,12 --exclude-from /exclude.conf ::"{hostname}-{now:%Y-%m-%dT%H:%M:%S}" .
cd -
borg prune --list --stats --keep-daily=7 --keep-weekly=4 --keep-monthly=12 --keep-yearly=5
borg compact --threshold=5 --cleanup-commits

btrfs subvolume delete /snapshot/source

echo "Finished backup script at `date`"
