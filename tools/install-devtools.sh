#!/usr/bin/env bash
# ==============================================================================
# Install everyday developer tools on Debian/Ubuntu:
#   base    curl wget zip unzip 7zip
#   docker  docker.io + compose plugin, user added to the docker group
#   node    nodejs + npm (from the distro, so no extra websites are needed)
#   pnpm    npm install -g pnpm
#   bun     npm install -g bun
# Safe to run more than once. Everything comes from the distro's apt mirrors and
# the npm registry (no curl-to-shell installers).
#
# Usage:  sudo bash install-devtools.sh
#         sudo bash install-devtools.sh --only base,docker
#         sudo bash install-devtools.sh --skip bun
# ==============================================================================

set -euo pipefail

ITEMS=(base docker node pnpm bun)
SELECT=""
SKIP=""

log()  { echo "    $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[-] $*" >&2; exit 1; }

usage() {
  cat << 'EOF'
Usage: sudo bash install-devtools.sh [OPTIONS]

Items (in this order): base, docker, node, pnpm, bun

  --only a,b     install only these items
  --skip a,b     leave these items out
  -h, --help     this text

pnpm and bun need node, so they are installed with it (or skipped if npm is missing).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --only)    SELECT="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --skip)    SKIP="${2:?--skip needs a comma-separated list}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Run with sudo."
command -v apt-get >/dev/null 2>&1 || die "This script needs apt (Debian or Ubuntu)."

in_list() {  # in_list <item> <comma-list>
  case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

validate() {  # validate <comma-list>
  local m k found
  for m in ${1//,/ }; do
    found=0
    for k in "${ITEMS[@]}"; do [ "$k" = "$m" ] && found=1; done
    [ "$found" = 1 ] || die "Unknown item '$m'. Items: ${ITEMS[*]}"
  done
}
[ -z "$SELECT" ] || validate "$SELECT"
[ -z "$SKIP" ] || validate "$SKIP"

want() {  # want <item>
  if [ -n "$SELECT" ] && ! in_list "$1" "$SELECT"; then return 1; fi
  if [ -n "$SKIP" ] && in_list "$1" "$SKIP"; then return 1; fi
  return 0
}

# First package name in the argument list that apt knows about.
first_available() {
  local p
  for p in "$@"; do
    if apt-cache show "$p" >/dev/null 2>&1; then echo "$p"; return 0; fi
  done
  return 1
}

# The normal (non-root) user, so they get docker access.
TARGET_USER="${SUDO_USER:-}"
[ "$TARGET_USER" != "root" ] || TARGET_USER=""

export DEBIAN_FRONTEND=noninteractive
echo "[+] Updating the package index"
apt-get update -y

if want base; then
  echo "[+] Base tools: curl wget zip unzip 7zip"
  # The package is called 7zip on newer releases and p7zip-full on older ones.
  sevenzip="$(first_available 7zip p7zip-full)" || die "No 7zip package found in apt."
  apt-get install -y ca-certificates curl wget zip unzip "$sevenzip"
fi

if want docker; then
  echo "[+] Docker"
  apt-get install -y docker.io
  compose="$(first_available docker-compose-v2 docker-compose-plugin docker-compose || true)"
  if [ -n "$compose" ]; then
    apt-get install -y "$compose"
  else
    warn "No docker compose package found in apt; skipping it."
  fi
  systemctl enable --now docker
  if [ -n "$TARGET_USER" ]; then
    usermod -aG docker "$TARGET_USER"
    log "$TARGET_USER was added to the docker group: log out and back in to use docker without sudo."
  else
    warn "Could not tell which user to add to the docker group. Run: sudo usermod -aG docker <user>"
  fi
fi

if want node; then
  echo "[+] Node.js and npm"
  apt-get install -y nodejs npm
fi

# pnpm and bun are npm packages, so they only work once npm exists.
npm_install() {  # npm_install <command> <npm package>
  if command -v "$1" >/dev/null 2>&1; then
    log "$1 already installed: $("$1" --version 2>/dev/null | head -n1)"
    return 0
  fi
  command -v npm >/dev/null 2>&1 || { warn "npm is not installed; skipping $2 (install the 'node' item first)."; return 0; }
  echo "[+] $2 (npm install -g)"
  npm install -g "$2"
}

if want pnpm; then npm_install pnpm pnpm; fi
if want bun;  then npm_install bun bun; fi

echo
echo "== Installed =="
for c in curl wget zip unzip 7z docker node npm pnpm bun; do
  if command -v "$c" >/dev/null 2>&1; then
    case "$c" in
      curl|wget|zip|unzip|7z) printf '  %-6s present\n' "$c" ;;
      *)                      printf '  %-6s %s\n' "$c" "$("$c" --version 2>/dev/null | head -n1)" ;;
    esac
  else
    printf '  %-6s not installed\n' "$c"
  fi
done
if docker compose version >/dev/null 2>&1; then
  printf '  %-6s %s\n' "compose" "$(docker compose version | head -n1)"
elif command -v docker-compose >/dev/null 2>&1; then
  printf '  %-6s %s\n' "compose" "$(docker-compose --version | head -n1)"
fi
echo
echo "Next: the repo's docker hardening (published ports on 127.0.0.1) runs with:"
echo "  sudo bash optimize.sh --only docker"
