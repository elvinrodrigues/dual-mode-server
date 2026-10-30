#!/usr/bin/env bash
# Module: cockpit. Web console on port 9090.

mod_cockpit() {
  systemctl enable --now cockpit.socket
  log "NOTE: Cockpit cannot list Docker containers (plugin discontinued). Use Portainer if you want that."
  return 0
}
