#!/usr/bin/env bash
# Debian support files. Tested on Debian 13 (Trixie) only.
# A new distro provides the same names; see docs in README.md.

SSH_SERVICE="ssh"
ADMIN_GROUP="sudo"
EARLYOOM_CONF="/etc/default/earlyoom"

distro_update_index() {
  apt-get update -y
}

distro_install_base() {
  apt-get install -y openssh-server xrdp xorgxrdp ufw zram-tools earlyoom \
    fail2ban smartmontools unattended-upgrades curl git ca-certificates python3
}

# --no-install-recommends keeps PackageKit and friends out of small RAM.
distro_install_cockpit() {
  apt-get install -y --no-install-recommends cockpit
}

distro_install_xfce() {
  apt-get install -y xfce4
}

distro_zram() {
  backup /etc/default/zramswap
  cat > /etc/default/zramswap << EOF
ALGO=zstd
PERCENT=$ZRAM_PERCENT
PRIORITY=100
EOF
  systemctl restart zramswap || warn "zramswap restart failed (check: systemctl status zramswap)"
  return 0
}

distro_auto_updates() {
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
  return 0
}

# Adds a "Headless Server Mode" entry to the GRUB menu.
distro_grub_headless() {
  if [ -z "$ROOT_UUID" ] || [ ! -e /vmlinuz ] || [ ! -e /initrd.img ] || mountpoint -q /boot; then
    warn "Unusual boot layout (separate /boot or missing /vmlinuz): skipping GRUB entry."
    warn "Alternative:  sudo systemctl set-default multi-user.target   (boot headless always)"
    return 0
  fi

  # Own file, so an existing /etc/grub.d/40_custom is left untouched.
  cat > /etc/grub.d/41_headless << EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry 'Debian GNU/Linux (Headless Server Mode - No GUI)' --class debian --class gnu-linux --class gnu --class os {
    load_video
    insmod gzio
    insmod part_msdos
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux   /vmlinuz root=UUID=$ROOT_UUID ro quiet systemd.unit=multi-user.target
    initrd  /initrd.img
}
EOF
  chmod +x /etc/grub.d/41_headless

  # Remove the entry an earlier version put into 40_custom, if it is still there.
  if grep -q 'Headless Server Mode' /etc/grub.d/40_custom 2>/dev/null; then
    backup /etc/grub.d/40_custom
    printf '#!/bin/sh\nexec tail -n +3 $0\n# This file provides an easy way to add custom menu entries.\n' > /etc/grub.d/40_custom
    chmod +x /etc/grub.d/40_custom
  fi

  if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
  fi
  update-grub
  return 0
}
