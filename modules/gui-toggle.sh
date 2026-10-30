#!/usr/bin/env bash
# Module: gui-toggle. Installs gui-stop / gui-start.

mod_gui_toggle() {
  cat > /usr/local/bin/gui-stop << 'EOF'
#!/bin/bash
# Usage: gui-stop        stop the local desktop
#        gui-stop --all  also end every remote desktop (XRDP) session
read -rp "This closes the local desktop (unsaved work is lost). Continue? [y/N] " a
[[ "$a" =~ ^[Yy]$ ]] || exit 0
sudo systemctl isolate multi-user.target
if [[ "${1:-}" == "--all" ]]; then
    sudo systemctl stop xrdp xrdp-sesman
    echo "[+] Remote desktop sessions ended."
fi
echo "[+] Desktop stopped. Memory now:"
free -h
EOF
  cat > /usr/local/bin/gui-start << 'EOF'
#!/bin/bash
sudo systemctl start xrdp 2>/dev/null || true
sudo systemctl isolate graphical.target
echo "[+] Desktop started."
EOF
  chmod +x /usr/local/bin/gui-stop /usr/local/bin/gui-start
  return 0
}
