#!/usr/bin/env bash
# Module: disk. Disk, CPU and housekeeping tuning.

mod_disk() {
  # noatime on the root filesystem
  if grep -qE '^\S+\s+/\s+ext4' /etc/fstab \
     && ! grep -E '^\S+\s+/\s+ext4' /etc/fstab | grep -q noatime; then
    backup /etc/fstab
    sed -i -E '/^\S+\s+\/\s+ext4/ s/(errors=remount-ro|defaults)/noatime,\1/' /etc/fstab
    mount -o remount / || warn "remount failed; fstab will apply on next boot."
  fi

  # bfq keeps the desktop responsive while Docker writes to a slow HDD
  cat > /etc/udev/rules.d/60-iosched.rules << 'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
  udevadm control --reload-rules && udevadm trigger --subsystem-match=block --action=change || true

  # Cap journal size so logs don't fill the disk
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/size.conf << 'EOF'
[Journal]
SystemMaxUse=200M
EOF
  systemctl restart systemd-journald

  # SMART monitoring
  systemctl enable --now smartmontools 2>/dev/null || systemctl enable --now smartd 2>/dev/null || true

  distro_auto_updates

  if [ "$PERF_GOVERNOR" = "1" ]; then
    cat > /etc/systemd/system/cpu-performance.service << 'EOF'
[Unit]
Description=Set CPU Scaling Governor to Performance
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now cpu-performance.service || true
  fi

  # Always-on machine: no sleep
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

  if [ "$DISABLE_UNUSED" = "1" ]; then
    local svc
    for svc in cups cups-browsed bluetooth ModemManager avahi-daemon; do
      systemctl disable --now "$svc.service" 2>/dev/null || true
    done
    log "Disabled unused services (cups, bluetooth, ModemManager, avahi)."
  fi
  return 0
}
