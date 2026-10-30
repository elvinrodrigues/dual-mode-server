#!/usr/bin/env bash
# Shared helpers. Sourced by optimize.sh; not meant to be run directly.

STAMP="$(date +%Y%m%d-%H%M%S)"

log()  { echo "    $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[-] $*" >&2; exit 1; }

# Copy an existing file aside before we replace it.
backup() {
  if [ -e "$1" ]; then
    cp -a "$1" "$1.bak.$STAMP"
  fi
  return 0
}

# Fills in everything the modules need to know about this machine.
detect_system() {
  CURRENT_USER="${SUDO_USER:-student}"
  USER_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
  ROOT_UUID="$(findmnt -no UUID / || true)"

  NET_IF="$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
  IP_ADDR=""
  LOCAL_NET=""
  if [ -n "$NET_IF" ]; then
    IP_ADDR="$(ip -4 -br addr show dev "$NET_IF" 2>/dev/null | awk '{print $3}' | cut -d/ -f1 || true)"
    LOCAL_NET="$(ip -4 route show dev "$NET_IF" scope link 2>/dev/null | awk 'NR==1{print $1}' || true)"
  fi
  ALLOWED_NETS="${ALLOWED_NETS:-$LOCAL_NET}"

  # The machine you are SSHed in from must stay reachable, or enabling the
  # firewall locks you out.
  SSH_CLIENT_IP=""
  if [ -n "${SSH_CONNECTION:-}" ]; then
    SSH_CLIENT_IP="${SSH_CONNECTION%% *}"
  fi

  # Memory-dependent tuning, so one script suits 4 GB and 8 GB machines.
  MEM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  if [ "$MEM_MB" -le 6144 ]; then
    SWAPPINESS=150
    ZRAM_PERCENT=50
  else
    SWAPPINESS=100
    ZRAM_PERCENT=25
  fi
  return 0
}
