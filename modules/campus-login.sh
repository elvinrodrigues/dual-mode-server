#!/usr/bin/env bash
# Module: campus-login (optional; not part of --all).
# Keeps a captive-portal network (college/hostel wifi) logged in. Installs:
#   /usr/local/bin/campus-login-run   the login check (run by the timer)
#   /usr/local/bin/campus-login       front end: edit | show | status
#   campus-login.service + .timer     run the check every 2 minutes
#   /etc/campus-login.conf            portal address and accounts (never in git)

mod_campus_login() {
  if [ ! -e /etc/campus-login.conf ]; then
    install -m 600 /dev/null /etc/campus-login.conf
    cat > /etc/campus-login.conf << 'EOF'
# Fill these in with: sudo campus-login edit
ACCOUNTS=(
  'username:password'
)
PORTAL="http://<portal-ip>:<port>"
EOF
    log "Created /etc/campus-login.conf (placeholders). Run: sudo campus-login edit"
  else
    chmod 600 /etc/campus-login.conf
  fi

  backup /usr/local/bin/campus-login-run
  cat > /usr/local/bin/campus-login-run << 'EOF'
#!/bin/bash
# Log in to the captive portal if the network is not online. Quiet when online.
CONF="${CAMPUS_LOGIN_CONF:-/etc/campus-login.conf}"
[ -r "$CONF" ] || { echo "Cannot read $CONF" >&2; exit 1; }
# shellcheck source=/dev/null
. "$CONF"

say() { echo "$*"; logger -t campus-login -- "$*"; }
online() {
  [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204)" = "204" ]
}
# Escape \ and " for curl's config-file syntax.
esc() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }

if [ -z "${PORTAL:-}" ] || [[ "$PORTAL" == *"<"* ]] || [ "${#ACCOUNTS[@]}" -eq 0 ]; then
  say "Not configured. Run: sudo campus-login edit"
  exit 0
fi

online && exit 0

for acct in "${ACCOUNTS[@]}"; do
  u="${acct%%:*}"
  p="${acct#*:}"
  [ "$u" = "username" ] && continue
  # Credentials go through stdin, so they never show up in 'ps'.
  resp="$(printf 'url = "%s/login.xml"\ndata = "mode=191&producttype=0&a=%s000"\ndata-urlencode = "username=%s"\ndata-urlencode = "password=%s"\nmax-time = 10\n' \
    "$(esc "$PORTAL")" "$(date +%s)" "$(esc "$u")" "$(esc "$p")" | curl -s -K - | tr '\n' ' ')"
  sleep 2
  # The portal says LIVE when the login worked, even if the internet check is
  # blocked by the campus network.
  if [[ "$resp" == *"[CDATA[LIVE]]"* ]] || online; then
    say "Logged in as $u"
    exit 0
  fi
  msg="$(printf '%s' "$resp" | sed -n 's/.*<message><!\[CDATA\[\(.*\)\]\]><\/message>.*/\1/p' | cut -c1-120)"
  if [ -z "$resp" ]; then
    msg="no reply from portal (wrong address or port?)"
  fi
  say "Login failed for $u: ${msg:-unrecognised portal reply}"
done
say "All accounts failed"
exit 1
EOF
  chmod 700 /usr/local/bin/campus-login-run

  backup /usr/local/bin/campus-login
  cat > /usr/local/bin/campus-login << 'EOF'
#!/bin/bash
# campus-login            run the login check now
# campus-login edit       open the accounts file
# campus-login show       print the accounts file (passwords visible)
# campus-login status     show recent login attempts
case "${1:-}" in
  "")      exec /usr/local/bin/campus-login-run ;;
  edit)    "${EDITOR:-nano}" /etc/campus-login.conf
           echo "Saved. Run 'sudo campus-login' to apply now." ;;
  show)    cat /etc/campus-login.conf ;;
  status)  journalctl -t campus-login -n 10 --no-pager ;;
  *)       echo "Usage: sudo campus-login [edit|show|status]"; exit 1 ;;
esac
EOF
  chmod 700 /usr/local/bin/campus-login

  cat > /etc/systemd/system/campus-login.service << 'EOF'
[Unit]
Description=College portal auto-login
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/campus-login-run
EOF
  cat > /etc/systemd/system/campus-login.timer << 'EOF'
[Unit]
Description=Check campus portal login every 2 minutes

[Timer]
OnBootSec=30s
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now campus-login.timer
  log "Next: sudo campus-login edit   (then: sudo campus-login, and sudo campus-login status)"
  return 0
}
