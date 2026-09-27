#!/bin/bash

# Read mountinfo from stdin and fill the caller's associative array. Kernel
# escapes protect whitespace and backslashes in the mount-point field.
snapshot_mounted_subvolumes() {
    local source=${1%/} mount remainder _ignored
    local -n discovered=$2
    while IFS=' ' read -r _ignored _ignored _ignored _ignored mount remainder; do
        [[ $remainder == *' - btrfs '* ]] || continue
        printf -v mount '%b' "$mount"
        if [[ $mount == "$source/"* && $mount != "$source/" ]]; then
            # The nameref fills the caller's array.
            # shellcheck disable=SC2034
            discovered["${mount#"$source/"}"]=1
        fi
    done
}

snapshot_create() (
    local source target parent name directory child relative inode original
    local -a pending
    local -A mounts=()
    unset GLOBIGNORE
    shopt -s dotglob nullglob
    IFS= read -r -d '' source < <(realpath -ez -- "$1") || return 1
    target=$2
    while [[ $target == */ && $target != / ]]; do target=${target%/}; done
    name=${target##*/}
    parent=${target%/*}
    [[ $target == */* ]] || parent=.
    IFS= read -r -d '' parent < <(realpath -ez -- "${parent:-/}") || return 1
    target=${parent%/}/$name
    if [[ -e $target || -L $target ]]; then
        printf 'Snapshot destination already exists: %s\n' "$target" >&2
        return 1
    fi
    snapshot_mounted_subvolumes "$source" mounts < /proc/self/mountinfo || return 1
    btrfs subvolume snapshot "$source" "$target" || return 1
    pending=("$target")
    while (( ${#pending[@]} )); do
        directory=${pending[-1]}
        unset 'pending[-1]'
        if [[ ! -r $directory || ! -x $directory ]]; then
            printf 'Cannot traverse snapshot directory: %s\n' "$directory" >&2
            return 1
        fi
        for child in "$directory"/*; do
            [[ -d $child && ! -L $child ]] || continue
            relative=${child#"$target/"}
            inode=$(stat -c %i -- "$child") || return 1
            # Unsnapshotted children have inode 2. A mounted subvolume may
            # instead hide an ordinary directory in its parent's snapshot.
            if [[ $inode == 2 || ${mounts[$relative]:-} == 1 ]]; then
                original=${source%/}/$relative
                if [[ -L $original ]]; then
                    printf 'Subvolume changed into a symlink: %s\n' "$original" >&2
                    return 1
                fi
                # Never recurse into the scratch snapshot, even below a child.
                if [[ $original -ef $target ]]; then
                    rmdir -- "$child" || return 1
                    continue
                fi
                # Refuse to discard data hidden beneath a mounted subvolume.
                rmdir -- "$child" || return 1
                btrfs subvolume snapshot "$original" "$child" || return 1
            fi
            pending+=("$child")
        done
    done
)

snapshot_delete() (
    local target=$1 directory child inode index
    local -a pending subvolumes
    unset GLOBIGNORE
    shopt -s dotglob nullglob
    while [[ $target == */ && $target != / ]]; do target=${target%/}; done
    if [[ -L $target ]]; then
        printf 'Refusing to delete a symlink as a snapshot: %s\n' "$target" >&2
        return 1
    fi
    btrfs subvolume show "$target" > /dev/null || return 1
    pending=("$target")
    subvolumes=("$target")
    while (( ${#pending[@]} )); do
        directory=${pending[-1]}
        unset 'pending[-1]'
        if [[ ! -r $directory || ! -x $directory ]]; then
            printf 'Cannot traverse snapshot directory: %s\n' "$directory" >&2
            return 1
        fi
        for child in "$directory"/*; do
            [[ -d $child && ! -L $child ]] || continue
            inode=$(stat -c %i -- "$child") || return 1
            [[ $inode != 256 ]] || subvolumes+=("$child")
            pending+=("$child")
        done
    done
    # Reverse discovery order puts every child before its parent.
    for ((index = ${#subvolumes[@]} - 1; index >= 0; index--)); do
        btrfs subvolume delete "${subvolumes[index]}" || return 1
    done
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        create) [[ $# == 3 ]] && snapshot_create "$2" "$3" ;;
        delete) [[ $# == 2 ]] && snapshot_delete "$2" ;;
        *) echo 'Expected create SOURCE TARGET or delete TARGET.' >&2; exit 1 ;;
    esac
fi
