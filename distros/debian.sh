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

distro_install_cinnamon() {
  apt-get install -y cinnamon
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
    python3 - /etc/grub.d/40_custom << 'PY'
import sys, re
path = sys.argv[1]
with open(path, "r") as f:
    lines = f.readlines()
out = []
in_block = False
depth = 0
found = False
for line in lines:
    if not in_block:
        if re.match(r"^\s*menuentry\s+['\"].*Headless Server Mode", line):
            in_block = True
            found = True
            depth = line.count("{") - line.count("}")
            continue
        out.append(line)
    else:
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            in_block = False
            continue
if found:
    with open(path, "w") as f:
        f.writelines(out)
PY
  fi

  # Show the menu for 5 seconds. Ubuntu/Mint hide it by default
  # (GRUB_TIMEOUT_STYLE=hidden), which makes the headless entry hard to reach.
  backup /etc/default/grub
  if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
  else
    echo 'GRUB_TIMEOUT=5' >> /etc/default/grub
  fi
  if grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
  else
    echo 'GRUB_TIMEOUT_STYLE=menu' >> /etc/default/grub
  fi
  update-grub
  return 0
}
