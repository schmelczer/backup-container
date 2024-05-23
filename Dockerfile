FROM alpine:3.18.2

USER root

RUN apk --no-cache add btrfs-progs openssh borgbackup bash coreutils

COPY id_rsa /id_rsa
COPY ssh_config /etc/ssh/
COPY src /src
COPY exclude.conf /exclude.conf

ENTRYPOINT ["sh", "-c", "/src/schedule.sh"]
