#!/bin/bash

set -euo pipefail

: "${ARCHIVE_PREFIX:?Set ARCHIVE_PREFIX to a non-empty archive prefix}"
export BORG_HOST_ID=${BORG_HOST_ID:-$ARCHIVE_PREFIX}

# Resolve Borg's cache settings before backups change directory.
base_dir=${BORG_BASE_DIR-${HOME:-/root}}
cache_home=${base_dir:+$base_dir/}.cache
if [[ -z ${BORG_BASE_DIR:-} && -v XDG_CACHE_HOME ]]; then
    cache_home=$XDG_CACHE_HOME
fi
cache_dir=${BORG_CACHE_DIR-${cache_home:+$cache_home/}borg}
mkdir -p -- "$cache_dir"
export BORG_CACHE_DIR
BORG_CACHE_DIR=$(realpath -e -- "$cache_dir")

# This cache belongs exclusively to this container. The previous container
# must be stopped before startup; any remaining client-cache locks are orphaned.
shopt -s nullglob
for cache in "$BORG_CACHE_DIR"/*; do
    [[ -d $cache && ! -L $cache && ${cache##*/} =~ ^[0-9a-f]{64}$ ]] || continue
    grep -qx '\[cache\]' "$cache/config" || continue

    if [[ -d $cache/lock.exclusive ]]; then
        echo "Removing orphaned cache lock: $cache/lock.exclusive"
        rm -r -- "$cache/lock.exclusive"
    fi
    
    if [[ -e $cache/lock.roster ]]; then
        rm -- "$cache/lock.roster"
    fi
done

(( $# != 0 )) || set -- /src/schedule.sh
exec "$@"
