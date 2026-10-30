#!/usr/bin/env bash
# Module: docker. Docker's iptables rules run BEFORE the firewall, so a
# published port is open to the whole network. Default every published port to
# localhost instead, and cap log growth.

mod_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not installed; skipped."
    return 0
  fi

  mkdir -p /etc/docker
  local dj=/etc/docker/daemon.json
  if [ ! -f "$dj" ]; then
    echo '{}' > "$dj"
  fi
  cp -a "$dj" "$dj.before"
  backup "$dj"
  python3 - "$dj" << 'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    cfg = json.load(f)
cfg.setdefault("ip", "127.0.0.1")
cfg.setdefault("log-driver", "local")
cfg.setdefault("log-opts", {"max-size": "10m", "max-file": "3"})
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  if ! cmp -s "$dj" "$dj.before"; then
    log "daemon.json changed; restarting Docker (containers restart briefly)."
    systemctl restart docker
  fi
  rm -f "$dj.before"

  log "Published ports now bind to 127.0.0.1 by default."
  log "To expose one on purpose:  docker run -p 0.0.0.0:8080:80 ...   (and add a ufw rule)"
  if getent group docker >/dev/null 2>&1; then
    usermod -aG docker "$CURRENT_USER"
    log "$CURRENT_USER must log out and back in for docker group membership to apply."
  fi
  return 0
}
