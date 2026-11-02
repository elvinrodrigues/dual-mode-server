#!/usr/bin/env bash
# ==============================================================================
# Build a signed APT repository in site/ from every .deb in dist/.
#
# Usage:  bash packaging/build-apt-repo.sh
# Env:    GPG_KEY_ID   key to sign with (default: the first secret key found)
#         GNUPGHOME    keyring that holds that key
# Needs apt-utils (apt-ftparchive) and gnupg. site/ is ready for GitHub Pages.
# ==============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$REPO_DIR/site"
DIST=stable
ARCHES=(all amd64 arm64 armhf)   # the package is Architecture: all

die() { echo "[-] $*" >&2; exit 1; }
command -v apt-ftparchive > /dev/null || die "apt-ftparchive not found (install apt-utils)"
command -v gpg > /dev/null || die "gpg not found (install gnupg)"
compgen -G "$REPO_DIR/dist/*.deb" > /dev/null || die "No .deb in dist/ (run packaging/build-deb.sh first)"

GPG=(gpg --batch --yes ${GPG_KEY_ID:+--local-user "$GPG_KEY_ID"})
"${GPG[@]}" --list-secret-keys > /dev/null 2>&1 || die "No GPG secret key available to sign with"

rm -rf "$SITE"
mkdir -p "$SITE/pool/main"
cp "$REPO_DIR"/dist/*.deb "$SITE/pool/main/"

cd "$SITE"
for arch in "${ARCHES[@]}"; do
  dir="dists/$DIST/main/binary-$arch"
  mkdir -p "$dir"
  apt-ftparchive --arch "$arch" packages pool > "$dir/Packages"
  gzip -9kn "$dir/Packages"
done

apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=dual-mode-server" \
  -o "APT::FTPArchive::Release::Label=dual-mode-server" \
  -o "APT::FTPArchive::Release::Suite=$DIST" \
  -o "APT::FTPArchive::Release::Codename=$DIST" \
  -o "APT::FTPArchive::Release::Architectures=${ARCHES[*]}" \
  -o "APT::FTPArchive::Release::Components=main" \
  release "dists/$DIST" > "dists/$DIST/Release"

"${GPG[@]}" --clearsign -o "dists/$DIST/InRelease" "dists/$DIST/Release"
"${GPG[@]}" --detach-sign -o "dists/$DIST/Release.gpg" "dists/$DIST/Release"
"${GPG[@]}" --export > key.gpg   # binary keyring: apt reads it directly via signed-by

install -m 0644 "$REPO_DIR/packaging/install.sh" install.sh
touch .nojekyll
echo "[+] Built APT repository in $SITE"
