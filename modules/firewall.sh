#!/usr/bin/env bash
# Module: firewall. Management ports only from trusted networks.

mod_firewall() {
  # Remove broad rules an earlier version may have created (ignore if absent).
  local r
  for r in "22/tcp" "3389/tcp" "9090/tcp" "80/tcp" "443/tcp" "3000:3999/tcp"; do
    ufw --force delete allow "$r" >/dev/null 2>&1 || true
  done

  ufw default deny incoming
  ufw default allow outgoing

  local sources
  if [ "$ALLOW_ANY" = "1" ]; then
    sources="any"
  else
    sources="$ALLOWED_NETS"
  fi

  # Keep the current SSH session alive no matter what.
  if [ -n "$SSH_CLIENT_IP" ]; then
    ufw allow from "$SSH_CLIENT_IP" to any port 22 proto tcp comment "SSH current client"
  fi

  local src
  for src in $sources; do
    ufw allow from "$src" to any port 22        proto tcp comment "SSH"
    ufw allow from "$src" to any port 3389      proto tcp comment "XRDP"
    ufw allow from "$src" to any port 9090      proto tcp comment "Cockpit"
    ufw allow from "$src" to any port 80        proto tcp comment "HTTP"
    ufw allow from "$src" to any port 443       proto tcp comment "HTTPS"
    ufw allow from "$src" to any port 3000:3999 proto tcp comment "App dev ports"
  done
  ufw --force enable
  return 0
}
