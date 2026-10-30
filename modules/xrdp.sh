#!/usr/bin/env bash
# Module: xrdp. Remote desktop session for the admin user.

mod_xrdp() {
  adduser xrdp ssl-cert >/dev/null 2>&1 || true

  backup "$USER_HOME/.xsession"
  case "$RDP_DESKTOP" in
    xfce) echo "startxfce4" > "$USER_HOME/.xsession" ;;
    *)    echo "cinnamon-session" > "$USER_HOME/.xsession" ;;
  esac
  chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME/.xsession"

  # Stops colour-profile and package-refresh prompts in remote sessions.
  mkdir -p /etc/polkit-1/rules.d
  backup /etc/polkit-1/rules.d/45-allow-colord.rules
  cat > /etc/polkit-1/rules.d/45-allow-colord.rules << EOF
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.color-manager.create-device" ||
         action.id == "org.freedesktop.color-manager.create-profile" ||
         action.id == "org.freedesktop.color-manager.delete-device" ||
         action.id == "org.freedesktop.color-manager.delete-profile" ||
         action.id == "org.freedesktop.color-manager.modify-device" ||
         action.id == "org.freedesktop.color-manager.modify-profile" ||
         action.id == "org.freedesktop.packagekit.system-sources-refresh") &&
        subject.isInGroup("$ADMIN_GROUP")) {
        return polkit.Result.YES;
    }
});
EOF

  systemctl enable --now xrdp
  log "NOTE: do not log in over XRDP as '$CURRENT_USER' while '$CURRENT_USER' is logged in at the"
  log "      physical screen (black screen). Run gui-stop first, or use a second account."
  return 0
}
