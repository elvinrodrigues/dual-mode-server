#!/usr/bin/env bash
# ==============================================================================
# Run on your laptop. Shows which club PCs are reachable over Headscale and
# whether SSH key login works. Changes nothing.
# Usage: bash check-pcs.sh [pc1 pc2 ...]   (aliases from ~/.ssh/config)
# ==============================================================================

ok()   { printf '  [ OK ] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; }
info() { printf '  [ .. ] %s\n' "$*"; }

HOSTS=("$@")
[ ${#HOSTS[@]} -gt 0 ] || HOSTS=(pc1 pc2 pc3)

for h in "${HOSTS[@]}"; do
  ip=$(ssh -G "$h" 2>/dev/null | awk '$1=="hostname"{print $2}')
  if [ -z "$ip" ] || [ "$ip" = "$h" ]; then
    bad "$h: no HostName in ~/.ssh/config"
    continue
  fi
  if ! ping -c1 -W2 "$ip" >/dev/null 2>&1; then
    bad "$h ($ip) is offline"
    continue
  fi
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true >/dev/null 2>&1; then
    ok "$h ($ip) is online, key login works"
  else
    info "$h ($ip) is online, key login not set up (run: ssh-copy-id $h)"
  fi
done
