# My backup container

Snapshot a [BTRFS](https://docs.kernel.org/filesystems/btrfs.html) volume from a [Docker container](https://www.docker.com/) and robustly back it up to multiple [BorgBackup](https://borgbackup.readthedocs.io/en/stable/index.html) repositories on a schedule.

## Quick start

- Check out [docker-compose.yml](docker-compose.yml) and set the environment variables according to your needs
- Update the password in the [.env](config/.env) file
- Adjust the [exclude.conf](conifg/exclude.conf) file to match your needs
- Run `docker compose --env-file ./config/default.env up`

## Background

I've been using this setup for the past year and have managed to avoid disaster by restoring all my data. This is all thanks to the excellent backup tool called BorgBackup. The scripts in the this repository serve as an opinionated thin wrapper around it. The Docker image I provide here is generic enough to be used verbatim in many self-hosting setups. However, it's just a thin wrapper and a set of configs that work together well. It's been a long journey for me to find a backup setup that works for me, so I make this available to save others from pitfalls and serve as a potenrial starting point for your own self-hosted backup container.

## Features

- Back up the snapshot of a BTRFS volume to avoid files changing during backup
  > I self-host multiple databases and this is the most feasible way of avoiding data corruption
- Schedule the backup so that it keeps running automatically
- Keep a weekly rotated log of all previous runs
- Back up the same source to multiple BorgBackup repositories

### Multi-target backups

In case we don't have disk-level redundancy and would still wish to follow the [3-2-1 rule](https://en.wikipedia.org/wiki/Backup), we have to back up the same source folder to multiple targets. For instance, I don't have a RAID setup but instead back up an SSD to [rsync.net](rsync.net) and a local HDD at the same time.

You can see in the [docker-compose.yml](docker-compose.yml) file that we can configure multi-target backups by setting the environment variables: `BORG_REPO_0`, `BORG_REPO_1`, `BORG_PASSPHRASE_0`, `BORG_PASSPHRASE_1`, etc.

The backup script first takes `BORG_REPO_0` and the corresponding env vars and sets up the [`BORG_REPO`](https://borgbackup.readthedocs.io/en/stable/usage/general.html#repository-urls), `BORG_REMOTE_PATH`, and `BORG_PASSPHRASE` environment variables for `borg`. Once the backup finished (successfully or otherwise), the script checks whether `BORG_REPO_1` exists, if so, it sets `BORG_REPO` and the other env vars to their expected values and backs up again. The script keeps going to `BORG_REPO_2`, `BORG_REPO_3` and so on as long as these are set. Otherwise, it unsets the previous `BORG_REPO` and corresponding env vars and goes to sleep.

Thus, the following sets of environment variables are valid for multi-target backups:

- ```sh
    - BORG_PASSPHRASE=$PASSWORD
    - BORG_REPO=/local-backup
  ```

  > This just backs up to a local repository

- ```sh
    - BORG_PASSPHRASE_0=$PASSWORD
    - BORG_REPO_0=/local-backup
  ```

  > This just backs up to a local repository

- ```sh
    - BORG_PASSPHRASE_0=$PASSWORD
    - BORG_REPO_0=/local-backup

    - BORG_PASSPHRASE_1=$PASSWORD2
    - BORG_REPO_1=/local-backup2
  ```

  > This backs up to two different local repositories

- ```sh
    - BORG_PASSPHRASE_0=$PASSWORD
    - BORG_REMOTE_PATH_0=borg1
    - BORG_REPO_0=my-username@my-username.rsync.net:~/backup

    - BORG_PASSPHRASE_1=$PASSWORD
    - BORG_REPO_1=/local-backup
  ```

  > This first back up to a remote repository, then to a local one

## Repository layout

- src
  - backup.sh: Creates a BorgBackup repository if it doesn't exist, snapshots the BTRFS volume, backs up your data, and removes old backups.
  - backup-wrapper.sh: Runs backup.sh for every BorgBackup repository provided through environment variables.
  - schedule.sh: Persists the logs of backup-wrapper.sh and runs it in a while True.

## Related resources

- I like this video on how to install Debian with BTRFS https://www.youtube.com/watch?v=MoWApyUb5w8. Of course, a BTRFS disk can be created after installation as well.
- rsync.net has a special discount when using BorgBackup: https://www.rsync.net/products/borg.html
- Checking out the documentation of BorgBackup is worth it: https://www.borgbackup.org/demo.html, especially the description of [borg create](https://borgbackup.readthedocs.io/en/stable/usage/create.html#description)
