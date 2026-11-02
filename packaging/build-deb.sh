#!/usr/bin/env bash
# ==============================================================================
# Build dual-mode-server_<version>_all.deb into dist/.
#
# Usage:  bash packaging/build-deb.sh [VERSION]
# VERSION defaults to the latest git tag (without the leading "v"), else 0.1.0.
# Needs dpkg-deb (package "dpkg"; on Debian/Ubuntu it is already installed).
# ==============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG=dual-mode-server
LIB_DIR=usr/lib/$PKG

command -v dpkg-deb > /dev/null || { echo "[-] dpkg-deb not found (install the dpkg package)" >&2; exit 1; }

VERSION="${1:-$(git -C "$REPO_DIR" describe --tags --abbrev=0 2> /dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
[[ "$VERSION" =~ ^[0-9][A-Za-z0-9.+~-]*$ ]] || { echo "[-] Bad version: $VERSION" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Scripts keep locating lib/ and modules/ relative to themselves, so the whole
# tree is installed under /usr/lib and thin wrappers go on the PATH.
install -d "$STAGE/$LIB_DIR" "$STAGE/usr/bin" "$STAGE/usr/share/doc/$PKG" "$STAGE/DEBIAN"
cp -r "$REPO_DIR"/{setup.sh,optimize.sh,distros,lib,modules,tools} "$STAGE/$LIB_DIR/"
install -m 0755 "$REPO_DIR/packaging/dual-mode-server" "$STAGE/usr/bin/dual-mode-server"
install -m 0755 "$REPO_DIR/packaging/dual-mode-optimize" "$STAGE/usr/bin/dual-mode-optimize"
install -m 0644 "$REPO_DIR/README.md" "$STAGE/usr/share/doc/$PKG/README.md"
install -m 0644 "$REPO_DIR/LICENSE" "$STAGE/usr/share/doc/$PKG/copyright"
find "$STAGE/$LIB_DIR" -type d -exec chmod 0755 {} +
find "$STAGE/$LIB_DIR" -type f -exec chmod 0644 {} +
chmod 0755 "$STAGE"/$LIB_DIR/{setup.sh,optimize.sh} "$STAGE"/$LIB_DIR/tools/*.sh

cat > "$STAGE/DEBIAN/control" << CONTROL
Package: $PKG
Version: $VERSION
Section: admin
Priority: optional
Architecture: all
Depends: bash, coreutils
Maintainer: Elvin Rodrigues <elvinrodrigues3456@gmail.com>
Description: Headless and remote-GUI server setup scripts for small Linux PCs
 Installs the dual-mode-server scripts. Nothing is changed on the system
 until you run dual-mode-server or dual-mode-optimize yourself.
CONTROL

mkdir -p "$REPO_DIR/dist"
OUT="$REPO_DIR/dist/${PKG}_${VERSION}_all.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT" > /dev/null
echo "[+] Built $OUT"
