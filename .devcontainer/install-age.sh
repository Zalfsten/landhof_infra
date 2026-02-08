#!/usr/bin/env bash
set -euo pipefail

echo "Installing latest age..."
ARCH=$(dpkg --print-architecture)
VERSION=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep -Po '"tag_name": "v\K[0-9.]+')
ASSET="age-v${VERSION}-linux-${ARCH}.tar.gz"

echo "Downloading ${ASSET}..."
curl -LO "https://github.com/FiloSottile/age/releases/download/v${VERSION}/${ASSET}"
tar -xzf "${ASSET}"
mv age/age age/age-keygen /usr/local/bin/
rm -rf age "${ASSET}"
echo "age ${VERSION} installed successfully."