#!/usr/bin/env bash
# Module: packages. Uses the distro_* functions from distros/<name>.sh.

mod_packages() {
  distro_update_index
  distro_install_base
  distro_install_cockpit
  if [ "$RDP_DESKTOP" = "xfce" ]; then
    distro_install_xfce
  elif ! command -v cinnamon-session >/dev/null 2>&1; then
    distro_install_cinnamon
  fi
  return 0
}
