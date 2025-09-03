#!/usr/bin/env bash
# install-fastfetch.sh — gotchi helper to install Fastfetch (.deb only)

set -euo pipefail

echo "Hello trainer! I’m here to help install Fastfetch, the cool system fetch tool for gotchis."

# 🛡 System check: Debian-based?
if ! command -v dpkg >/dev/null || ! command -v apt-get >/dev/null; then
  echo -e "\e[31mOops! This system doesn't look Debian-based. (Missing dpkg or apt)\e[0m"
  echo -e "\e[31mTry installing Fastfetch manually from:\e[0m"
  echo -e "\e[31m   https://github.com/fastfetch-cli/fastfetch/releases/latest\e[0m"
  echo -e "\e[31mIf you're on Alpine, Arch, etc — this script won't help, sorry!\e[0m"
  exit 1
fi

ARCH="$(dpkg --print-architecture)"

# Normalize arch naming (Debian: arm64 → fastfetch: aarch64)
if [[ "$ARCH" == "arm64" ]]; then
  ARCH="aarch64"
fi

# 🛰️ Get latest version tag dynamically
VERSION="$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep -Po '"tag_name": "\K[^"]+' || true)"

if [[ -z "$VERSION" ]]; then
  echo -e "\e[31mCouldn't detect latest Fastfetch version from GitHub.\e[0m"
  echo -e "\e[31m   Check manually: https://github.com/fastfetch-cli/fastfetch/releases\e[0m"
  exit 1
fi

BASE_URL="https://github.com/fastfetch-cli/fastfetch/releases/download/${VERSION}"
PKG_NAME="fastfetch-linux-${ARCH}.deb"
TMP="/tmp/${PKG_NAME}"

echo "Target arch: $ARCH"
echo "Latest version: $VERSION"

# Already installed?
if command -v fastfetch >/dev/null 2>&1; then
  echo "Fastfetch is already installed at: $(command -v fastfetch)"
  fastfetch
  exit 0
fi

# Check if .deb exists for this arch
if ! curl -fsI "${BASE_URL}/${PKG_NAME}" >/dev/null; then
  echo -e "\e[31mFastfetch doesn't provide a .deb for your arch: $ARCH\e[0m"
  echo -e "\e[31mFallback: download a .tar.gz or compile from source.\e[0m"
  echo -e "\e[31m   https://github.com/fastfetch-cli/fastfetch/releases/latest\e[0m"
  exit 1
fi

# Download + install
echo "Downloading: ${PKG_NAME}"
curl -L "${BASE_URL}/${PKG_NAME}" -o "$TMP"
echo "Installing..."
if ! sudo dpkg -i "$TMP"; then
  echo "dpkg failed — trying to fix broken deps with apt..."
  sudo apt-get -f install -y
fi

# Cleanup
rm -f "$TMP"

# Final check
if ! command -v fastfetch >/dev/null; then
  echo -e "\e[31mSomething went wrong. fastfetch is still not installed.\e[0m"
  echo -e "\e[31mTry manual install: https://github.com/fastfetch-cli/fastfetch/releases/latest\e[0m"
  exit 1
fi

echo -e "\e[32mFastfetch ${VERSION} installed successfully!\e[0m"
echo "Let’s see it in action:"
fastfetch
