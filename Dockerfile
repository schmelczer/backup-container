FROM alpine:3.22.0

# this is the default, but just to be explicit
USER root

RUN apk --no-cache add \
    btrfs-progs \
    openssh \
    bash \
    coreutils \
    borgbackup=1.4.0-r0

COPY src /src
COPY config/ssh_config /etc/ssh/
COPY config/exclude.conf /exclude.conf


# Add healthcheck to verify backup completed within allowed time
ENV MAX_BACKUP_AGE_SECONDS=86400
HEALTHCHECK --interval=10s --timeout=10s --start-period=1h CMD /src/healthcheck.sh

ENTRYPOINT ["sh", "-c", "/src/schedule.sh"]
