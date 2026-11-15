#!/bin/sh
# Starts the SFTP server. SFTP_PUBLIC_KEY is the public key allowed to log in.
set -eu

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
fi

keys=/etc/ssh/authorized_keys/upload
touch "$keys"
if [ -n "${SFTP_PUBLIC_KEY:-}" ] && ! grep -qxF "$SFTP_PUBLIC_KEY" "$keys"; then
  printf '%s\n' "$SFTP_PUBLIC_KEY" >>"$keys"
fi

# The volume is mounted at /srv/sftp/site. Hand its top folder to the upload user.
chown upload: /srv/sftp/site

exec /usr/sbin/sshd -D -e
