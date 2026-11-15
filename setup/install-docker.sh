#!/usr/bin/env bash
# Installs Docker Engine on the server (Ubuntu), following the official guide
# the slides point to: https://docs.docker.com/engine/install/ubuntu/
#
# Run this yourself ON THE SERVER. It needs your sudo password:
#
#   bash ~/Projects/Kubernetes/setup/install-docker.sh
#
# What it changes on the machine:
#   - adds Docker's apt repository and signing key
#   - installs docker-ce, the CLI, containerd, buildx and the compose plugin
#   - installs git (needed from day 9)
#   - adds your user to the "docker" group, so docker runs without sudo.
#     Members of that group effectively have root on this machine.
set -euo pipefail

if [ "$(uname -s)" != "Linux" ]; then
  echo "Run this on the server, not on the Mac." >&2
  exit 1
fi

echo "== Updating package lists (slide 75: apt update)"
sudo apt-get update

echo "== Installing prerequisites"
sudo apt-get install -y ca-certificates curl git

echo "== Adding Docker's signing key and apt repository"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "== Installing Docker Engine"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "== Letting $USER use docker without sudo"
sudo usermod -aG docker "$USER"

echo "== Test (slide 85)"
sudo docker run --rm hello-world

echo
echo "Done. The group change applies to new logins, so new SSH sessions can run docker directly."
