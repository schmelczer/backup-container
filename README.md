# My backup container [![Docker](https://github.com/schmelczer/backup-container/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/schmelczer/backup-container/actions/workflows/docker-publish.yml)

Create a snapshot of a [BTRFS](https://docs.kernel.org/filesystems/btrfs.html) volume from a [Docker container](https://www.docker.com/) and robustly back it up to multiple [BorgBackup](https://borgbackup.readthedocs.io/en/stable/index.html) repositories on a schedule.

## Quick start

1. Review and modify the [docker-compose.yml](docker-compose.yml) file to set your environment variables as needed
2. Customise the [exclude.conf](config/exclude.conf) according to your requirements
3. Execute the command `docker compose --env-file ./config/default.env up` to spin up the container

## Background

Over the past 2 years, this backup setup has enabled me to successfully restore all my data after incidents. This is all thanks to the excellent backup tool called BorgBackup. The scripts in this repository serve as an opinionated thin wrapper around it. The Docker image provided can be used directly in various self-hosting setups. It's designed to be a simple and effective tool for those looking to establish a reliable backup system, saving time and avoiding common pitfalls.

## Features

- **Snapshotting**: Takes a snapshot of a BTRFS volume to ensure file consistency during backups.
  > I self-host multiple databases and this is the most feasible way of avoiding data corruption.
- **Scheduled Backups**: Automates backups according to a defined schedule.
- **Log Rotation**: Maintains weekly logs of all backup activities.
- **Multi-Repository Backups**: Allows backups to multiple BorgBackup repositories simultaneously.
- **Healtcheck**: The healthcheck is based on the time of the last successful backup.

### Multi-target backups

To adhere to the [3-2-1 backup rule](https://en.wikipedia.org/wiki/Backup) without disk-level redundancy, you can configure backups to multiple destinations. For example, backups can be sent simultaneously to [rsync.net](rsync.net) and a local HDD.

The [`docker-compose.yml`](docker-compose.yml) file demonstrates how to set up multiple backup targets using environment variables such as `BORG_REPO_0`, `BORG_REPO_1`, `BORG_PASSPHRASE_0`, `BORG_PASSPHRASE_1`, and so forth. The backup script sequentially handles each repository defined by the environment variables, ensuring your source volume is backed up across all specified targets.

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

### Healthcheck

When a backup succeeds, it writes down the success time to a file. The healthcheck compares the current time with the last backup's time and it reports healthy if the two are between `MAX_BACKUP_AGE_SECONDS` of each other. This value can be overriden.

## Repository layout

- src
  - [backup.sh](src/backup.sh): Creates a new BorgBackup repository if none exists, takes a snapshot of the BTRFS volume, performs the backup, and prunes old backups.
  - [backup-wrapper.sh](src/backup-wrapper.sh): Executes backup.sh for each repository configured via environment variables.
  - [schedule.sh](src/schedule.sh): Manages and logs the operation of backup-wrapper.sh and runs it in a continuous loop.
- config
  - [exclude.conf](config/exclude.conf): Exclude list for `borg`. Files matching these patterns won't be backed up.
  - [ssh_config](config/ssh_config): SSH config for improving remote backup robustness.

## Related resources

- Learn how to install Debian with BTRFS in this helpful [video tutorial](https://www.youtube.com/watch?v=MoWApyUb5w8). Note that a BTRFS disk can also be created post-installation.
- [rsync.net](https://www.rsync.net/products/borg.html) offers a special discount for BorgBackup users: [BorgBackup at rsync.net](https://www.rsync.net/products/borg.html).
- Explore detailed BorgBackup documentation and demos: [BorgBackup Documentation](https://www.borgbackup.org/demo.html), including a comprehensive guide on [`borg create`](https://borgbackup.readthedocs.io/en/stable/usage/create.html#description).

## Development

Create a new tag:

```sh
export TAG=vX.X.X
git tag -a $TAG -m "Release $TAG"
git push origin $TAG
```
