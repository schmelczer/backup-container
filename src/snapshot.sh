#!/bin/bash

snapshot_create() (
    local source target=$2 children mount remainder inode _ignored
    IFS= read -r -d '' source < <(realpath -ez -- "$1") || return 1
    while [[ $target == */ && $target != / ]]; do target=${target%/}; done
    if [[ -e $target || -L $target ]]; then
        printf 'Snapshot destination already exists: %s\n' "$target" >&2
        return 1
    fi

    children=$(btrfs subvolume list -o "$source") || return 1
    if [[ -n $children ]]; then
        printf 'INFO: Nested subvolumes under %s will be omitted from the snapshot; continuing backup:\n%s\n' "$source" "$children"
    fi

    # Mounted subvolumes may live elsewhere and are absent from the list above.
    while IFS=' ' read -r _ignored _ignored _ignored _ignored mount remainder; do
        [[ $remainder == *' - btrfs '* ]] || continue
        printf -v mount '%b' "$mount"
        [[ $mount == "${source%/}/"* && $mount != "$source" ]] || continue
        inode=$(stat -c %i -- "$mount") || return 1
        if [[ $inode == 256 && -d $mount ]]; then
            printf 'INFO: Mounted subvolume contents will be omitted from the snapshot; continuing backup: %s\n' "$mount"
        fi
    done < /proc/self/mountinfo || return 1

    btrfs subvolume snapshot "$source" "$target"
)

snapshot_delete() (
    local target=$1
    while [[ $target == */ && $target != / ]]; do target=${target%/}; done
    if [[ -L $target ]]; then
        printf 'Refusing to delete a symlink as a snapshot: %s\n' "$target" >&2
        return 1
    fi
    btrfs subvolume delete "$target"
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        create) [[ $# == 3 ]] && snapshot_create "$2" "$3" ;;
        delete) [[ $# == 2 ]] && snapshot_delete "$2" ;;
        *) echo 'Expected create SOURCE TARGET or delete TARGET.' >&2; exit 1 ;;
    esac
fi
