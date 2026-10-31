#!/usr/bin/env bash
# ==============================================================================
# Read-only health check for the server setup. Changes nothing.
# Usage: sudo bash check-server.sh
# ==============================================================================

ok()   { printf '  [ OK ] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; }
info() { printf '  [ .. ] %s\n' "$*"; }

check_active() {
  if systemctl is-active --quiet "$1"; then ok "$1 is running"; else bad "$1 is NOT running"; fi
}

echo "== Services =="
for s in ssh xrdp cockpit.socket earlyoom fail2ban docker zramswap ufw; do
  check_active "$s"
done

echo
echo "== Memory =="
free -h | sed 's/^/  /'
zramctl 2>/dev/null | sed 's/^/  /'
sw=$(sysctl -n vm.swappiness); pc=$(sysctl -n vm.page-cluster)
[ "$sw" -ge 100 ] && ok "vm.swappiness = $sw" || bad "vm.swappiness = $sw (expected >= 100 with zram)"
[ "$pc" -eq 0 ]   && ok "vm.page-cluster = 0" || bad "vm.page-cluster = $pc (expected 0)"
info "tcp congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"

echo
echo "== Disk =="
for d in /sys/block/sd?; do
  [ -e "$d/queue/scheduler" ] && info "$(basename "$d") scheduler: $(cat "$d/queue/scheduler")"
done
grep -qE '\s/\s+ext4.*noatime' /proc/mounts && ok "root mounted with noatime" || info "root not mounted with noatime"
if command -v smartctl >/dev/null 2>&1; then
  smartctl -H /dev/sda 2>/dev/null | grep -i 'result' | sed 's/^/  /'
  smartctl -A /dev/sda 2>/dev/null | grep -Ei 'Reallocated_Sector|Current_Pending|Offline_Uncorrectable' | sed 's/^/  /'
fi

echo
echo "== Firewall =="
ufw status numbered 2>/dev/null | sed 's/^/  /'

echo
echo "== Docker exposure =="
if command -v docker >/dev/null 2>&1; then
  if grep -q '"ip": *"127.0.0.1"' /etc/docker/daemon.json 2>/dev/null; then
    ok "Docker publishes ports on 127.0.0.1 by default"
  else
    bad "Docker daemon.json has no \"ip\": \"127.0.0.1\" (published ports are open to the whole LAN)"
  fi
  echo "  Containers publishing ports:"
  docker ps --format '    {{.Names}}  {{.Ports}}' 2>/dev/null
fi

echo
echo "== Listening on all interfaces (reachable from the campus network) =="
ss -tlnH 2>/dev/null | awk '$4 ~ /^(0\.0\.0\.0|\[::\]|\*):/ {print "  " $4}' | sort -u

echo
echo "== SSH =="
if sshd -T 2>/dev/null | grep -q '^passwordauthentication no'; then
  ok "SSH password login disabled (keys only)"
else
  info "SSH password login still enabled (add a key with ssh-copy-id, then re-run optimize.sh --debian --only ssh)"
fi

echo
echo "== Boot menu =="
grep -h "menuentry '" /boot/grub/grub.cfg 2>/dev/null | sed "s/^/  /; s/ --class.*//" | head -20

echo
echo "== Default boot target: $(systemctl get-default) =="
