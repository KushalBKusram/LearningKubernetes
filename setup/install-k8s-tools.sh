#!/usr/bin/env bash
# Installs kubectl, kind and helm into ~/.local/bin on the server. Needed from day 19.
# No sudo: the binaries are downloaded from the projects' own release sites, their
# checksums are verified, and they are copied into one folder in your home directory.
#
# Run it on the server:   bash setup/install-k8s-tools.sh
# Install somewhere else: COURSE_BIN_DIR=/some/dir bash setup/install-k8s-tools.sh
#
# It installs the latest release of each tool. The course was built and tested with
# kubectl 1.37.2, kind 0.33.0 and helm 4.3.2.
set -euo pipefail

BIN=${COURSE_BIN_DIR:-$HOME/.local/bin}
ARCH=$(uname -m)
case $ARCH in
  x86_64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) echo "Unsupported CPU architecture: $ARCH" >&2; exit 1 ;;
esac
if [ "$(uname -s)" != "Linux" ]; then
  echo "Run this on the Linux server, not on your computer." >&2
  exit 1
fi
for tool in curl jq sha256sum tar; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done

mkdir -p "$BIN"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

echo "== kubectl"
kv=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLO "https://dl.k8s.io/release/$kv/bin/linux/$ARCH/kubectl"
echo "$(curl -fsSL "https://dl.k8s.io/release/$kv/bin/linux/$ARCH/kubectl.sha256")  kubectl" | sha256sum -c -
install -m 0755 kubectl "$BIN/kubectl"

echo "== kind"
kind=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r .tag_name)
curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/$kind/kind-linux-$ARCH"
curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/$kind/kind-linux-$ARCH.sha256sum" | sha256sum -c -
install -m 0755 "kind-linux-$ARCH" "$BIN/kind"

echo "== helm"
helm=$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r .tag_name)
tarball="helm-$helm-linux-$ARCH.tar.gz"
curl -fsSLO "https://get.helm.sh/$tarball"
echo "$(curl -fsSL "https://get.helm.sh/$tarball.sha256sum" | cut -d' ' -f1)  $tarball" | sha256sum -c -
tar -xzf "$tarball"
install -m 0755 "linux-$ARCH/helm" "$BIN/helm"

echo
echo "Installed into $BIN:"
"$BIN/kubectl" version --client -o json | jq -r '"  kubectl " + .clientVersion.gitVersion'
"$BIN/kind" version | sed 's/^/  /'
"$BIN/helm" version --short | sed 's/^/  helm /'
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Note: $BIN is not on your PATH. The course scripts add it themselves (setup/lib.sh)." ;;
esac
