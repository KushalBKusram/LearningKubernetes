# The stand-in for AWS Transfer Family (slide 342): an SFTP server that
# exposes the shared volume to the outside. Built on the official ubuntu image.
FROM ubuntu:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* \
 # Host keys are created at first start, not baked into the image.
 && rm -f /etc/ssh/ssh_host_* \
 && mkdir -p /run/sshd /srv/sftp/site /etc/ssh/authorized_keys \
 # The SFTP user shares uid 33 with www-data, the user PHP runs as, so both
 # can read and write the same files on the volume.
 && useradd --non-unique --uid 33 --gid 33 --no-create-home --home-dir /site --shell /usr/sbin/nologin upload \
 # "*" = no password, but not locked: key login stays possible.
 && usermod --password '*' upload

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
