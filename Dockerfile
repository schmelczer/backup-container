FROM alpine:3.20.0

USER root

RUN apk --no-cache add btrfs-progs openssh borgbackup bash coreutils

COPY src /src
COPY config/ssh_config /etc/ssh/
COPY config/exclude.conf /exclude.conf

ENTRYPOINT ["sh", "-c", "/src/schedule.sh"]
