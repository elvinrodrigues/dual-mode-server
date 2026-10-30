# dual-mode-server

One script to turn a small Linux PC into a **dual-mode server**: boot headless or with a desktop, reach it over SSH, remote desktop (XRDP) and a web panel (Cockpit), all on the same shared system (same files, same Docker daemon, same ports).

Tuned for small-memory machines (tested on 4 GB RAM with a 5900 RPM HDD) and sized automatically for larger ones.

> **Status:** tested on **Debian 13 (Trixie)** only, on one machine. Other distros are not supported yet. The scripts change SSH, firewall, boot and kernel settings: **read them first and try them in a VM**.

## Quick start

Run it at the machine itself the first time, not over SSH.

```bash
git clone https://github.com/elvinrodrigues/dual-mode-server.git
cd dual-mode-server
sudo bash optimize.sh --debian --all
sudo reboot
sudo bash tools/check-server.sh
```

### Before you run it: SSH keys
Password login is only switched off if a key is already installed. From your laptop:

```bash
ssh-keygen -t ed25519          # set a passphrase
ssh-copy-id user@<server-ip>
```

Then run (or re-run) the script. The key stays protected by its passphrase, so don't create it on a shared PC without one.

## Usage

```
sudo bash optimize.sh [DISTRO] [MODULES] [OPTIONS]
```

| Option | Meaning |
| :--- | :--- |
| `--debian` / `--distro NAME` | Pick the distro support files (default: detected). |
| `--all` | Run every module. |
| `--only a,b,c` | Run only these modules. |
| `--skip a,b` | Leave these modules out. |
| `--list` | Show modules and supported distros. |
| `--allowed-nets "A B"` | Networks allowed through the firewall (default: this PC's subnet). |
| `--allow-any` | Open management ports to any source. Not for shared networks. |
| `--rdp-desktop NAME` | `cinnamon` (default) or `xfce` (lighter). |
| `--no-governor` | Skip the always-`performance` CPU governor. |
| `--disable-unused` | Disable cups, bluetooth, ModemManager and avahi. |

Examples:

```bash
sudo bash optimize.sh --debian --all
sudo bash optimize.sh --debian --all --skip grub,docker
sudo bash optimize.sh --debian --only ssh,firewall --allowed-nets "10.0.0.0/24 192.168.1.0/24"
sudo bash optimize.sh --list
```

## Modules

| Module | What it does |
| :--- | :--- |
| `packages` | Installs ssh, xrdp, cockpit, ufw, zram, earlyoom, fail2ban, smartmontools. |
| `ssh` | Keys-only login (if a key exists), no root login, `fail2ban`. |
| `xrdp` | Remote desktop session and the polkit rule that silences prompts. |
| `cockpit` | Web console on port 9090. |
| `docker` | Published ports bind to `127.0.0.1` by default; log size capped. |
| `memory` | ZRAM, sysctl (sized from RAM), `earlyoom`. |
| `disk` | `noatime`, `bfq`, journal cap, SMART, auto-updates, CPU governor, no sleep. |
| `grub` | Extra "Headless Server Mode" boot entry. |
| `gui-toggle` | `gui-stop` / `gui-start` commands. |
| `firewall` | UFW: management ports only from trusted networks. |

Every file that gets replaced is first copied to `<file>.bak.<timestamp>` (skipped if it already matches the latest backup). The script is safe to run more than once.

## Why these choices

- **Docker bypasses UFW.** Its iptables rules run first, so a published port is reachable from the whole network. Binding to `127.0.0.1` by default closes that.
- **ZRAM + high swappiness.** With compressed swap in RAM, swapping is cheap and dropping file cache means slow disk reads, so the kernel should prefer ZRAM.
- **`earlyoom`.** Kills the biggest process early instead of letting a small-RAM machine freeze while it thrashes.
- **Firewall by subnet.** On a shared network, only trusted networks reach SSH, RDP and Cockpit. The IP you are SSHed in from is always allowed so you cannot lock yourself out.

More detail is in [`docs/ANALYSIS.md`](docs/ANALYSIS.md).

## Known limits

- Do not open an XRDP desktop as user X while X is logged in at the physical screen; run `gui-stop` first or use a second account.
- Cockpit does not manage Docker containers (the plugin was discontinued). Use Portainer if you want a container UI.
- After a power cut the PC only restarts by itself if the BIOS option **After Power Loss** is set to **Power On**.
- Do not forward ports to the internet. For outside access use an outbound tunnel (Tailscale for yourself, Cloudflare Tunnel for a website), and check your network's rules first.

## Layout

```
optimize.sh        entry point
lib/common.sh      helpers and machine detection
modules/           one file per module
distros/debian.sh  package names, ZRAM, boot loader for Debian
tools/             check-server.sh (read-only health check)
docs/              analysis and notes
```

## Adding a distro

Copy `distros/debian.sh` to `distros/<name>.sh` and provide the same names: `SSH_SERVICE`, `ADMIN_GROUP`, `EARLYOOM_CONF`, `distro_update_index`, `distro_install_base`, `distro_install_cockpit`, `distro_install_xfce`, `distro_zram`, `distro_auto_updates` and `distro_grub_headless`. Test it before listing it as supported.

## License

MIT, see [LICENSE](LICENSE).
