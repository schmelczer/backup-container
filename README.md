# My backup container

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
- **Multi-Repository Backups**: Backs up to multiple BorgBackup repositories sequentially.
- **Healthcheck**: Reports failed backups and checks the age of the last successful backup.

### Multi-target backups

Set the required `ARCHIVE_PREFIX` environment variable to a non-empty prefix shared by all backup targets. Include any separator in the value: `ARCHIVE_PREFIX=my-host-` creates archives named `my-host-{now:%Y-%m-%dT%H:%M:%S}`. Pruning uses the glob `${ARCHIVE_PREFIX}*`, so retention rules only apply to matching archives. To continue pruning existing archives, set the prefix to their previous hostname followed by `-`.

To adhere to the [3-2-1 backup rule](https://en.wikipedia.org/wiki/Backup) without disk-level redundancy, you can configure backups to multiple destinations. For example, backups can be sent to [rsync.net](rsync.net) and a local HDD.

The [`docker-compose.yml`](docker-compose.yml) file demonstrates how to set up multiple backup targets using environment variables such as `BORG_REPO_0`, `BORG_REPO_1`, `BORG_PASSPHRASE_0`, `BORG_PASSPHRASE_1`, and so forth. The backup script sequentially handles each repository defined by the environment variables, ensuring your source volume is backed up across all specified targets.

The backup script first takes `BORG_REPO_0` and the corresponding env vars and sets up the [`BORG_REPO`](https://borgbackup.readthedocs.io/en/stable/usage/general.html#repository-urls), `BORG_REMOTE_PATH`, and `BORG_PASSPHRASE` environment variables for `borg`. Once the backup finished (successfully or otherwise), the script checks whether `BORG_REPO_1` exists, if so, it sets `BORG_REPO` and the other env vars to their expected values and backs up again. The script keeps going to `BORG_REPO_2`, `BORG_REPO_3` and so on as long as these are set. It then checks each repository with the corresponding environment before starting the next backup cycle.

Thus, the following sets of environment variables are valid for multi-target backups:

- ```sh
    - ARCHIVE_PREFIX=my-host-
    - BORG_PASSPHRASE=$PASSWORD
    - BORG_REPO=/local-backup
  ```

  > This just backs up to a local repository

- ```sh
    - ARCHIVE_PREFIX=my-host-
    - BORG_PASSPHRASE_0=$PASSWORD
    - BORG_REPO_0=/local-backup
  ```

  > This just backs up to a local repository

- ```sh
    - ARCHIVE_PREFIX=my-host-
    - BORG_PASSPHRASE_0=$PASSWORD
    - BORG_REPO_0=/local-backup

    - BORG_PASSPHRASE_1=$PASSWORD2
    - BORG_REPO_1=/local-backup2
  ```

  > This backs up to two different local repositories

- ```sh
    - ARCHIVE_PREFIX=my-host-
    - BORG_PASSPHRASE_0=$PASSWORD
    - BORG_REMOTE_PATH_0=borg1
    - BORG_REPO_0=my-username@my-username.rsync.net:~/backup

    - BORG_PASSPHRASE_1=$PASSWORD
    - BORG_REPO_1=/local-backup
  ```

  > This first back up to a remote repository, then to a local one

### Sharing repositories

Multiple containers can back up different sources to the same repository, using distinct, non-overlapping `ARCHIVE_PREFIX` values and separate cache and snapshot directories. Borg 1.4 serializes writes with repository locks. Each Borg command waits indefinitely for a repository or cache lock, with no maximum wait setting. Because Borg 1.4's CLI requires a finite wait per attempt, the wrapper retries lock timeouts every 60 seconds until the lock becomes available. Other failures stop that target and are reflected in container health.

### Checks between backups

After attempting every backup target, the wrapper runs `borg check --repository-only --max-duration=SECONDS --info` on each configured repository, including targets whose backup failed. Checks use the same credentials, remote executable and indefinite lock waiting as backups. They do not initialize, repair, prune or compact repositories. Any check warning or error immediately stops the cycle and the scheduler with Borg's nonzero exit status; later targets are not checked in that cycle. Lock contention continues waiting indefinitely.

Borg resumes partial checks from the last segment checked. These checks inspect segment checksums; they do not verify repository indexes, archive metadata or cryptographic data integrity, and do not replace periodic full checks. See [Borg's partial-check documentation](https://borgbackup.readthedocs.io/en/1.4.0/usage/check.html).

### Healthcheck

The container is healthy when no backup or repository-check failure is recorded and its last successful cycle is less than `MAX_BACKUP_AGE_SECONDS` old (default: `86400`, or one day). All configured targets must succeed. Set this to a positive integer that allows enough time for backups, checks and lock waits.

Before the first successful backup, the same limit provides a startup grace period, which ends immediately on a failed target or invalid configuration. A failure makes health checks fail even if a previous success or the startup timestamp is recent. Docker marks the container unhealthy after its configured healthcheck retries. The backup failure marker persists in `/health` across restarts and retries and is cleared only after all backups and scheduled checks succeed. Only then is the completion timestamp updated.

A failed repository check also creates `/health/check_failed`. While it exists, the wrapper refuses to start any backups or checks, including after Docker restarts the container. This prevents a later partial check from skipping a damaged segment and hiding the failure. Investigate the failure and complete full checks of the configured repositories before manually removing this marker from that container's health volume. Scheduled checks never clear it automatically.

## Repository layout

- src
  - [backup.sh](src/backup.sh): Creates a new BorgBackup repository if none exists, takes a snapshot of the BTRFS volume, performs the backup, and prunes old backups.
  - [backup-wrapper.sh](src/backup-wrapper.sh): Backs up all configured targets, then performs time-limited repository checks.
  - [borg-common.sh](src/borg-common.sh): Shares Borg SSH settings and indefinite lock waiting between backups and checks.
  - [schedule.sh](src/schedule.sh): Manages and logs the operation of backup-wrapper.sh and runs it in a continuous loop.
- config
  - [exclude.conf](config/exclude.conf): Exclude list for `borg`. Files matching these patterns won't be backed up.
  - [ssh_config](config/ssh_config): SSH config for improving remote backup robustness.

## Related resources

- Learn how to install Debian with BTRFS in this helpful [video tutorial](https://www.youtube.com/watch?v=MoWApyUb5w8). Note that a BTRFS disk can also be created post-installation.
- [rsync.net](https://www.rsync.net/products/borg.html) offers a special discount for BorgBackup users: [BorgBackup at rsync.net](https://www.rsync.net/products/borg.html).
- Explore detailed BorgBackup documentation and demos: [BorgBackup Documentation](https://www.borgbackup.org/demo.html), including a comprehensive guide on [`borg create`](https://borgbackup.readthedocs.io/en/stable/usage/create.html#description).

## Development

Run the healthcheck tests in a disposable container (backups are mocked):

```sh
docker build -t backup-healthcheck-tests .
tar -c tests | docker run --rm -i --network none --entrypoint /bin/bash \
  -e BACKUP_HEALTHCHECK_TEST=1 backup-healthcheck-tests \
  -c 'tar -x -C / && bash /tests/healthcheck.sh'
shellcheck src/*.sh tests/*.sh
```

Create a new tag:

```sh
export TAG=vX.X.X
git tag -a $TAG -m "Release $TAG"
git push origin $TAG
```
