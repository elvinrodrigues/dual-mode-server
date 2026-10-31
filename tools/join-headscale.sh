#!/usr/bin/env bash
# ==============================================================================
# Join this PC to the club's Headscale network (Tailscale client + Headscale
# server). Safe to run more than once.
#
# Usage:  sudo bash join-headscale.sh --hostname flcpc1
#         sudo bash join-headscale.sh --hostname flcpc1 --deb /media/usb/tailscale.deb
#         sudo bash join-headscale.sh --key-file ~/tailscale-join.key
#
# The pre-auth key is read from, in order: --key-file, $HEADSCALE_AUTHKEY, or a
# hidden prompt. It is never written into the repo. Create one in the Headscale
# container:  headscale preauthkeys create --user 1 --reusable --expiration 24h
# ==============================================================================

set -euo pipefail

SERVER_URL="https://ssh.finiteloop.club"
NODE_NAME="$(hostname -s)"
KEY_FILE=""
DEB_FILE=""
FORCE=0

log()  { echo "    $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[-] $*" >&2; exit 1; }

usage() {
  cat << 'EOF'
Usage: sudo bash join-headscale.sh [OPTIONS]

  --hostname NAME    name this PC gets on the network (default: this PC's hostname)
  --key-file FILE    read the pre-auth key from FILE (default: $HEADSCALE_AUTHKEY,
                     else a hidden prompt)
  --deb FILE         install Tailscale from this .deb if it is not installed
                     (for networks that block tailscale.com)
  --server URL       Headscale address (default: https://ssh.finiteloop.club)
  --force            re-register even if this PC is already connected
  -h, --help         this text
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --hostname) NODE_NAME="${2:?--hostname needs a value}"; shift 2 ;;
    --key-file) KEY_FILE="${2:?--key-file needs a value}"; shift 2 ;;
    --deb)      DEB_FILE="${2:?--deb needs a value}"; shift 2 ;;
    --server)   SERVER_URL="${2:?--server needs a value}"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; die "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Run with sudo."

# --- 1. Tailscale client -------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  if [ -n "$DEB_FILE" ]; then
    [ -f "$DEB_FILE" ] || die "No such file: $DEB_FILE"
    echo "[+] Installing Tailscale from $DEB_FILE"
    dpkg -i "$DEB_FILE" || apt-get -f install -y
  else
    die "Tailscale is not installed. Re-run with --deb /path/to/tailscale_*_amd64.deb (download it from pkgs.tailscale.com on another network)."
  fi
fi
log "Tailscale $(tailscale version | head -n1)"

echo "[+] Enabling tailscaled"
systemctl enable --now tailscaled

# --- 2. Can this network reach the Headscale server? ---------------------------
echo "[+] Checking $SERVER_URL"
if ! curl -fsS -m 15 "$SERVER_URL/health" >/dev/null; then
  die "Cannot reach $SERVER_URL/health from this network. Fix that first (DNS, proxy, firewall)."
fi
log "Headscale server reachable"

# --- 3. Join --------------------------------------------------------------------
if [ "$FORCE" -eq 0 ] && tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
  echo "[=] Already connected; skipping the join. Use --force to re-register."
else
  AUTHKEY=""
  if [ -n "$KEY_FILE" ]; then
    [ -r "$KEY_FILE" ] || die "Cannot read $KEY_FILE"
    AUTHKEY="$(tr -d '[:space:]' < "$KEY_FILE")"
  elif [ -n "${HEADSCALE_AUTHKEY:-}" ]; then
    AUTHKEY="$HEADSCALE_AUTHKEY"
  else
    read -r -s -p "Pre-auth key: " AUTHKEY
    echo
  fi
  [ -n "$AUTHKEY" ] || die "No pre-auth key given."

  UP_ARGS=(--login-server="$SERVER_URL" --hostname="$NODE_NAME")
  [ "$FORCE" -eq 1 ] && UP_ARGS+=(--force-reauth)

  echo "[+] Joining as $NODE_NAME"
  # Prefer a temp file so the key does not show up in the process list.
  if tailscale up --help 2>&1 | grep -q 'file:'; then
    KEYTMP="$(mktemp)"
    trap 'rm -f "$KEYTMP"' EXIT
    chmod 600 "$KEYTMP"
    printf '%s' "$AUTHKEY" > "$KEYTMP"
    tailscale up "${UP_ARGS[@]}" --authkey="file:$KEYTMP"
  else
    tailscale up "${UP_ARGS[@]}" --authkey="$AUTHKEY"
  fi
  unset AUTHKEY
fi

# --- 4. Firewall: let tailnet traffic reach SSH, RDP and Cockpit ----------------
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  echo "[+] Allowing traffic on tailscale0"
  ufw allow in on tailscale0 comment "Tailscale"
else
  log "ufw not active; no firewall rule added"
fi

# --- 5. Result --------------------------------------------------------------------
echo
echo "== Result =="
tailscale ip -4 | sed 's/^/  address: /'
tailscale status
echo
echo "Next: on the Headscale container run 'headscale nodes list' to confirm this PC appears."
