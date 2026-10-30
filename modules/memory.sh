#!/usr/bin/env bash
# Module: memory. ZRAM, sysctl and earlyoom, sized from the machine's RAM.

mod_memory() {
  distro_zram

  backup /etc/sysctl.d/99-server-optimization.conf
  cat > /etc/sysctl.d/99-server-optimization.conf << EOF
# --- Memory: swap is compressed RAM (zram), so prefer it over dropping file cache ---
vm.swappiness = $SWAPPINESS
vm.page-cluster = 0
vm.watermark_scale_factor = 125
vm.vfs_cache_pressure = 50

# --- Smooth dirty-page writeout for a slow HDD ---
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# --- Network ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
EOF
  modprobe tcp_bbr 2>/dev/null || true
  sysctl --system >/dev/null || warn "sysctl reported errors; run 'sudo sysctl --system' to see them."

  # earlyoom: kill the biggest offender early instead of freezing on the HDD
  backup "$EARLYOOM_CONF"
  cat > "$EARLYOOM_CONF" << 'EOF'
EARLYOOM_ARGS="-r 3600 -m 5 -s 10 --avoid '(^|/)(sshd|systemd|Xorg|xrdp|xrdp-sesman|dockerd|containerd|cockpit-ws)$' --prefer '(^|/)(node|bun|chrome|chromium|code)$'"
EOF
  systemctl enable --now earlyoom
  systemctl restart earlyoom
  log "RAM ${MEM_MB} MB: swappiness=$SWAPPINESS, zram=${ZRAM_PERCENT}% of RAM."
  return 0
}
