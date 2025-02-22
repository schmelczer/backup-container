FROM alpine:3.21.2

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

ENTRYPOINT ["sh", "-c", "/src/schedule.sh"]
