#!/usr/bin/env bash
# Adds the dual-mode-server APT repository on Debian/Ubuntu.
# Usage:  curl -fsSL https://apt.elvinrodrigues.dev/install.sh | sudo bash
# Then:   sudo apt install dual-mode-server

set -euo pipefail

BASE_URL="${DMS_REPO_URL:-https://apt.elvinrodrigues.dev}"
KEYRING=/etc/apt/keyrings/dual-mode-server.gpg
LIST=/etc/apt/sources.list.d/dual-mode-server.list

[ "$(id -u)" -eq 0 ] || { echo "[-] Run as root: curl -fsSL $BASE_URL/install.sh | sudo bash" >&2; exit 1; }
command -v apt-get > /dev/null || { echo "[-] This needs a Debian or Ubuntu system (apt)." >&2; exit 1; }
command -v curl > /dev/null || { apt-get update -qq && apt-get install -y -qq curl ca-certificates; }

install -d -m 0755 /etc/apt/keyrings
curl -fsSL "$BASE_URL/key.gpg" -o "$KEYRING"
chmod 0644 "$KEYRING"
echo "deb [signed-by=$KEYRING] $BASE_URL stable main" > "$LIST"
apt-get update -qq

echo "[+] Repository added. Install with:  sudo apt install dual-mode-server"
