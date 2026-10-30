#!/usr/bin/env bash
# Module: ssh. Hardening plus fail2ban.

mod_ssh() {
  systemctl enable --now "$SSH_SERVICE"
  mkdir -p /etc/ssh/sshd_config.d
  backup /etc/ssh/sshd_config.d/10-hardening.conf

  # Keys-only login, but ONLY if a key is already installed (otherwise you lock yourself out).
  local auth_keys="$USER_HOME/.ssh/authorized_keys"
  if [ -s "$auth_keys" ]; then
    cat > /etc/ssh/sshd_config.d/10-hardening.conf << 'EOF'
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 4
EOF
    if sshd -t; then
      systemctl reload "$SSH_SERVICE"
      log "SSH: password login disabled (key found in $auth_keys)."
    else
      warn "sshd config test failed; reverting hardening file."
      rm -f /etc/ssh/sshd_config.d/10-hardening.conf
    fi
  else
    warn "No SSH key for $CURRENT_USER yet, so password login stays ON."
    warn "From your laptop run:  ssh-copy-id $CURRENT_USER@${IP_ADDR:-<server-ip>}   then re-run this module."
    cat > /etc/ssh/sshd_config.d/10-hardening.conf << 'EOF'
PermitRootLogin no
MaxAuthTries 4
EOF
    if sshd -t; then
      systemctl reload "$SSH_SERVICE"
    else
      warn "sshd config test failed; reverting hardening file."
      rm -f /etc/ssh/sshd_config.d/10-hardening.conf
    fi
  fi

  # fail2ban for sshd (reads the journal, not auth.log)
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd-local.conf << EOF
[sshd]
enabled  = true
backend  = systemd
maxretry = 5
bantime  = 1h
ignoreip = 127.0.0.1/8 ::1 ${SSH_CLIENT_IP}
EOF
  systemctl enable --now fail2ban
  systemctl restart fail2ban
  return 0
}
