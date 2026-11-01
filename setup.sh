#!/usr/bin/env bash
# ==============================================================================
# One command for a fresh PC. Runs the repo's scripts in order:
#   1. optimize    optimize.sh --all          (SSH, firewall, memory, ...)
#   2. internet    campus-login module        (captive-portal auto-login)
#   3. tools       tools/install-devtools.sh  (docker, node, pnpm, bun, ...)
#                  then optimize.sh --only docker  (harden the new Docker)
#   4. headscale   tools/install-tailscale.sh + tools/join-headscale.sh
#
# Usage:  sudo bash setup.sh --all --hostname flcpc1
#         sudo bash setup.sh --only tools,headscale --hostname flcpc1
#         sudo bash setup.sh --all --skip internet --dry-run
# Needs sudo and git already installed (see "Fresh Debian install" in README.md).
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEPS=(optimize internet tools headscale)

log()  { echo "    $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[-] $*" >&2; exit 1; }

usage() {
  cat << 'EOF'
Usage: sudo bash setup.sh [STEPS] [OPTIONS]

Steps (run in this order):
  optimize    SSH hardening, firewall, memory, disk, boot menu (optimize.sh --all)
  internet    college wifi auto-login (campus-login); asks for the accounts
  tools       docker, node, pnpm, bun, curl, wget, zip, unzip, 7zip
  headscale   install Tailscale and join the club's Headscale network

Selecting steps (one of these is required):
  --all                  run every step
  --only a,b             run only these steps
  --skip a,b             leave these steps out

Options:
  --hostname NAME        name this PC gets on the Headscale network
                         (default: this PC's hostname)
  --key-file FILE        read the Headscale pre-auth key from FILE
                         (default: asked with a hidden prompt)
  --optimize-args "..."  extra options for optimize.sh, e.g. "--allowed-nets 10.0.0.0/24"
  --dry-run              show what would run, change nothing
  -h, --help             this text

If a step fails the script stops and says how to continue from that step.
EOF
}

SELECT=""
SKIP=""
NODE_NAME="$(hostname -s)"
KEY_FILE=""
OPTIMIZE_ARGS=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --all)           SELECT="all"; shift ;;
    --only)          SELECT="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --skip)          SKIP="${2:?--skip needs a comma-separated list}"; shift 2 ;;
    --hostname)      NODE_NAME="${2:?--hostname needs a value}"; shift 2 ;;
    --key-file)      KEY_FILE="${2:?--key-file needs a value}"; shift 2 ;;
    --optimize-args) OPTIMIZE_ARGS="${2:?--optimize-args needs a value}"; shift 2 ;;
    --dry-run)       DRY_RUN=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; die "Unknown option: $1" ;;
  esac
done

[ -n "$SELECT" ] || { usage; echo; die "Nothing selected. Add --all or --only <steps>."; }

in_list() {  # in_list <item> <comma-list>
  case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

validate() {  # validate <comma-list>
  local m k found
  for m in ${1//,/ }; do
    found=0
    for k in "${STEPS[@]}"; do [ "$k" = "$m" ] && found=1; done
    [ "$found" = 1 ] || die "Unknown step '$m'. Steps: ${STEPS[*]}"
  done
}
[ "$SELECT" = "all" ] || validate "$SELECT"
[ -z "$SKIP" ] || validate "$SKIP"

RUN=()
for s in "${STEPS[@]}"; do
  if [ "$SELECT" != "all" ] && ! in_list "$s" "$SELECT"; then continue; fi
  if [ -n "$SKIP" ] && in_list "$s" "$SKIP"; then continue; fi
  RUN+=("$s")
done
[ "${#RUN[@]}" -gt 0 ] || die "No steps left to run."

if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  die "Run with sudo: sudo bash setup.sh $*"
fi

# run <command...>: print it, and run it unless this is a dry run.
# Steps call it as "run ... || return 1" because set -e does not apply inside
# a function that is tested with "if !".
run() {
  echo "    \$ $*"
  [ "$DRY_RUN" -eq 1 ] || "$@"
}

step_optimize() {
  # shellcheck disable=SC2086  # OPTIMIZE_ARGS is meant to split into words
  run bash "$ROOT_DIR/optimize.sh" --all $OPTIMIZE_ARGS || return 1
}

step_internet() {
  run bash "$ROOT_DIR/optimize.sh" --only campus-login || return 1
  # The module leaves placeholder accounts. Ask for the real ones when someone is at the keyboard.
  if [ "$DRY_RUN" -eq 0 ] && grep -q "'username:password'" /etc/campus-login.conf 2>/dev/null; then
    if [ -t 0 ]; then
      echo "    Enter the portal address and your accounts (saved in /etc/campus-login.conf, mode 600)."
      campus-login edit
      campus-login || warn "Portal login did not succeed yet. Check: sudo campus-login status"
    else
      warn "Accounts not set. Later run: sudo campus-login edit"
    fi
  fi
}

step_tools() {
  run bash "$ROOT_DIR/tools/install-devtools.sh" || return 1
  # Docker now exists, so the repo's hardening (ports on 127.0.0.1) can apply.
  # shellcheck disable=SC2086
  run bash "$ROOT_DIR/optimize.sh" --only docker $OPTIMIZE_ARGS || return 1
}

step_headscale() {
  run bash "$ROOT_DIR/tools/install-tailscale.sh" || return 1
  local args=(--hostname "$NODE_NAME")
  [ -z "$KEY_FILE" ] || args+=(--key-file "$KEY_FILE")
  run bash "$ROOT_DIR/tools/join-headscale.sh" "${args[@]}" || return 1
}

echo "=========================================================="
echo " setup.sh: ${RUN[*]}"
[ "$DRY_RUN" -eq 0 ] || echo " DRY RUN: nothing will be changed"
echo "=========================================================="

for s in "${RUN[@]}"; do
  echo
  echo "== Step: $s =="
  if ! "step_$s"; then
    echo >&2
    die "Step '$s' failed. Fix the problem, then continue with:  sudo bash setup.sh --only ${RUN[*]// /,} (drop the steps already done)"
  fi
done

echo
echo "== Done =="
if [ "$DRY_RUN" -eq 1 ]; then
  echo "That was a dry run. Nothing changed."
else
  echo "Steps finished: ${RUN[*]}"
  echo "Reboot when convenient (boot menu, kernel and group changes):  sudo reboot"
  echo "Check the result:  sudo bash tools/check-server.sh"
fi
