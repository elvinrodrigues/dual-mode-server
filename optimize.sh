#!/usr/bin/env bash
# ==============================================================================
# dual-mode-server: headless + remote GUI server setup for small Linux PCs.
#
# Usage:  sudo bash optimize.sh --debian --all
#         sudo bash optimize.sh --debian --only ssh,firewall
#         sudo bash optimize.sh --list
# See --help for every option.
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES=(packages ssh xrdp cockpit docker memory disk grub gui-toggle firewall)

usage() {
  cat << 'EOF'
Usage: sudo bash optimize.sh [DISTRO] [MODULES] [OPTIONS]

Distro (default: detected from /etc/os-release):
  --debian               use the Debian support files (the only tested distro)
  --distro NAME          use distros/NAME.sh

Modules (one of --all / --only is required):
  --all                  run every module, in order
  --only a,b,c           run only these modules
  --skip a,b             leave these modules out
  --list                 show modules and supported distros

Options:
  --allowed-nets "A B"   networks allowed through the firewall
                         (default: this PC's own subnet)
  --allow-any            open the management ports to any source
                         (not for shared or campus networks)
  --rdp-desktop NAME     cinnamon (default) or xfce
  --no-governor          do not force the "performance" CPU governor
  --disable-unused       disable cups, bluetooth, ModemManager, avahi
  -h, --help             this text

The environment variables ALLOWED_NETS, ALLOW_ANY, RDP_DESKTOP, PERF_GOVERNOR
and DISABLE_UNUSED are still honoured. Every file that gets replaced is first
copied to <file>.bak.<timestamp>. Safe to run more than once.
EOF
}

describe_module() {
  case "$1" in
    packages)   echo "install packages (ssh, xrdp, cockpit, ufw, zram, earlyoom, ...)" ;;
    ssh)        echo "SSH hardening (keys-only if a key exists) + fail2ban" ;;
    xrdp)       echo "remote desktop session + polkit rule" ;;
    cockpit)    echo "web console on port 9090" ;;
    docker)     echo "bind published ports to localhost, cap container logs" ;;
    memory)     echo "ZRAM, sysctl tuning, earlyoom" ;;
    disk)       echo "noatime, bfq, journal cap, SMART, auto-updates, CPU governor" ;;
    grub)       echo "extra 'Headless Server Mode' boot menu entry" ;;
    gui-toggle) echo "gui-stop / gui-start commands" ;;
    firewall)   echo "UFW: management ports only from trusted networks" ;;
  esac
}

supported_distros() {
  local f
  for f in "$ROOT_DIR"/distros/*.sh; do
    basename "$f" .sh
  done | tr '\n' ' '
}

# Defaults (environment variables may pre-set them)
ALLOW_ANY="${ALLOW_ANY:-0}"
RDP_DESKTOP="${RDP_DESKTOP:-cinnamon}"
PERF_GOVERNOR="${PERF_GOVERNOR:-1}"
DISABLE_UNUSED="${DISABLE_UNUSED:-0}"
ALLOWED_NETS="${ALLOWED_NETS:-}"

DISTRO=""
SELECT=""
SKIP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --debian)         DISTRO="debian" ;;
    --distro)         DISTRO="${2:?--distro needs a name}"; shift ;;
    --all)            SELECT="all" ;;
    --only)           SELECT="${2:?--only needs a comma-separated list}"; shift ;;
    --skip)           SKIP="${2:?--skip needs a comma-separated list}"; shift ;;
    --allowed-nets)   ALLOWED_NETS="${2:?--allowed-nets needs a value}"; shift ;;
    --allow-any)      ALLOW_ANY=1 ;;
    --rdp-desktop)    RDP_DESKTOP="${2:?--rdp-desktop needs a name}"; shift ;;
    --no-governor)    PERF_GOVERNOR=0 ;;
    --disable-unused) DISABLE_UNUSED=1 ;;
    --list)
      echo "Modules (run in this order):"
      for m in "${MODULES[@]}"; do
        printf '  %-11s %s\n' "$m" "$(describe_module "$m")"
      done
      echo
      echo "Supported distros: $(supported_distros)"
      exit 0
      ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "[-] Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"
for f in "$ROOT_DIR"/modules/*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

if [ "$EUID" -ne 0 ]; then
  die "Please run with sudo: sudo bash $0 $*"
fi

if [ -z "$SELECT" ]; then
  usage
  echo
  die "Nothing selected. Add --all or --only <modules>."
fi

# --- Resolve distro ----------------------------------------------------------
resolve_distro() {
  if [ -n "$DISTRO" ]; then
    [ -f "$ROOT_DIR/distros/$DISTRO.sh" ] \
      || die "No support files for '$DISTRO'. Supported: $(supported_distros)"
    return 0
  fi
  [ -r /etc/os-release ] || die "Cannot detect the distro. Pass --debian or --distro NAME."
  local ID="" ID_LIKE="" cand
  # shellcheck source=/dev/null
  . /etc/os-release
  for cand in $ID $ID_LIKE; do
    if [ -f "$ROOT_DIR/distros/$cand.sh" ]; then
      DISTRO="$cand"
      if [ "$cand" != "$ID" ]; then
        warn "'$ID' is not tested; using the '$cand' support files. Review before relying on it."
      fi
      return 0
    fi
  done
  die "No support files for '$ID'. Supported: $(supported_distros)"
}
resolve_distro
# shellcheck source=/dev/null
. "$ROOT_DIR/distros/$DISTRO.sh"

# --- Resolve module list -----------------------------------------------------
in_list() {  # in_list <item> <comma-list>
  case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

validate_modules() {  # validate_modules <comma-list>
  local m
  for m in ${1//,/ }; do
    local found=0 k
    for k in "${MODULES[@]}"; do
      if [ "$k" = "$m" ]; then found=1; fi
    done
    [ "$found" = 1 ] || die "Unknown module '$m'. Run --list to see the modules."
  done
}

[ "$SELECT" = "all" ] || validate_modules "$SELECT"
[ -z "$SKIP" ] || validate_modules "$SKIP"

RUN=()
for m in "${MODULES[@]}"; do
  if [ "$SELECT" != "all" ] && ! in_list "$m" "$SELECT"; then continue; fi
  if [ -n "$SKIP" ] && in_list "$m" "$SKIP"; then continue; fi
  RUN+=("$m")
done
[ "${#RUN[@]}" -gt 0 ] || die "No modules left to run."

# --- Run ---------------------------------------------------------------------
detect_system
export DEBIAN_FRONTEND=noninteractive

echo "=========================================================="
echo " dual-mode-server"
echo " Distro: $DISTRO | User: $CURRENT_USER | RAM: ${MEM_MB} MB"
echo " Interface: ${NET_IF:-?} | IP: ${IP_ADDR:-?}"
if [ "$ALLOW_ANY" = 1 ]; then
  echo " Trusted networks: ANY SOURCE (open)"
else
  echo " Trusted networks: $ALLOWED_NETS"
fi
if [ -n "$SSH_CLIENT_IP" ]; then
  echo " Current SSH client (always allowed): $SSH_CLIENT_IP"
fi
echo " Modules: ${RUN[*]}"
echo "=========================================================="

if [ "$ALLOW_ANY" != 1 ] && [ -z "$ALLOWED_NETS" ]; then
  die "Could not detect the local subnet. Re-run with --allowed-nets \"x.x.x.x/yy\"."
fi

total=${#RUN[@]}
i=0
for m in "${RUN[@]}"; do
  i=$((i + 1))
  echo "[$i/$total] $m"
  "mod_${m//-/_}"
done

echo ""
echo "=========================================================="
echo " Done. Reboot to apply boot-menu and disk changes:  sudo reboot"
echo ""
echo "   SSH:       ssh $CURRENT_USER@${IP_ADDR:-<server-ip>}"
echo "   Desktop:   RDP to ${IP_ADDR:-<server-ip>}:3389"
echo "   Web panel: https://${IP_ADDR:-<server-ip>}:9090"
echo ""
echo " Check the result with:  sudo bash tools/check-server.sh"
echo "=========================================================="
