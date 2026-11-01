#!/usr/bin/env bash
# ==============================================================================
# Install the Tailscale client on Ubuntu or Debian through Tailscale's apt
# repository (pkgs.tailscale.com). Use this when `curl tailscale.com/install.sh`
# is blocked but the apt repository is reachable. Safe to run more than once.
# It only installs; join the network with join-headscale.sh afterwards.
#
# Usage:  sudo bash install-tailscale.sh
#         sudo bash install-tailscale.sh --deb /media/usb/tailscale_amd64.deb
# ==============================================================================

set -euo pipefail

DEB_FILE=""

log()  { echo "    $*"; }
die()  { echo "[-] $*" >&2; exit 1; }

usage() {
  cat << 'EOF'
Usage: sudo bash install-tailscale.sh [OPTIONS]

  --deb FILE   install from this .deb instead of the apt repository
               (for networks where pkgs.tailscale.com is blocked)
  -h, --help   this text
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --deb)     DEB_FILE="${2:?--deb needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Run with sudo."

if command -v tailscale >/dev/null 2>&1; then
  echo "[=] Tailscale is already installed: $(tailscale version | head -n1)"
  exit 0
fi

if [ -n "$DEB_FILE" ]; then
  [ -f "$DEB_FILE" ] || die "No such file: $DEB_FILE"
  echo "[+] Installing Tailscale from $DEB_FILE"
  dpkg -i "$DEB_FILE" || apt-get -f install -y
else
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) distro="$ID"; codename="${VERSION_CODENAME:-}" ;;
    *)             distro="ubuntu"; codename="${UBUNTU_CODENAME:-}" ;;
  esac
  [ -n "$codename" ] || die "Cannot tell this release's codename. Use --deb /path/to/tailscale_*_amd64.deb instead."

  base="https://pkgs.tailscale.com/stable/$distro/$codename"
  echo "[+] Adding the Tailscale apt repository ($distro $codename)"
  curl -fsSL "$base.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    || die "Could not download $base.noarmor.gpg (blocked network, or no repo for this release). Use --deb instead."
  curl -fsSL "$base.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list \
    || die "Could not download $base.tailscale-keyring.list. Use --deb instead."
  apt-get update
  apt-get install -y tailscale
fi

systemctl enable --now tailscaled
log "Installed: $(tailscale version | head -n1)"
echo "Next: sudo bash tools/join-headscale.sh --hostname <name>"
