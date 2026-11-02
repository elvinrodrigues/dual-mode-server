# dual-mode-server

Scripts to turn a small Linux PC into a **dual-mode server**: boot headless or with a desktop, reach it over SSH, remote desktop (XRDP) and a web panel (Cockpit), all on the same shared system (same files, same Docker daemon, same ports). `setup.sh` does a whole fresh PC in one command: server tuning, college wifi login, developer tools and joining the club's Headscale network.

Tuned for small-memory machines (tested on 4 GB RAM with a 5900 RPM HDD) and sized automatically for larger ones.

> **Status:** `optimize.sh` is tested on **Debian 13 (Trixie)** only, on one machine. `setup.sh` and the new `tools/` install scripts have only been checked with `--dry-run` (and a Tailscale join done by hand). Other distros are not supported yet. The scripts change SSH, firewall, boot and kernel settings: **read them first and try them in a VM**.

## Set up a fresh PC, start to finish

### 0. Before you start

- Debian is installed and the internet works. If the college wifi has a login page, log in to it in Firefox first.
- You have a **Headscale pre-auth key** for the club network. Create one in the Headscale container (Dokploy terminal) and copy it; do not share it:
  ```bash
  headscale preauthkeys create --user 1 --reusable --expiration 1h
  ```
- You have a name for this PC (for example `flcpc1`); every PC needs a different one.
- Optional: your SSH public key. Password login is only switched off once a key is installed (see [SSH keys](#ssh-keys)).

### 1. Install `sudo` and `git`

A fresh Debian has no `sudo` for your user and no `git`. Open this page in Firefox on the new PC and paste these one at a time. Replace `YOURUSERNAME` with the account you created during the install:

```bash
su -
```

```bash
apt update && apt install -y sudo git
```

```bash
usermod -aG sudo YOURUSERNAME
```

```bash
exit
```

Log out and back in (the group only applies to a new login), then check that `sudo` works:

```bash
sudo -v
```

If you left the root password empty during the install, the installer already set up `sudo`. Skip the `su -` part and run only `sudo apt update && sudo apt install -y git`.

### 2. Clone the repo

```bash
git clone https://github.com/elvinrodrigues/dual-mode-server.git
cd dual-mode-server
```

### 3. Run the setup

First look at what it will do. This changes nothing:

```bash
sudo bash setup.sh --all --hostname flcpc1 --dry-run
```

Then run it for real:

```bash
sudo bash setup.sh --all --hostname flcpc1
```

Run it at the machine itself the first time, not over SSH. It takes a while and asks you for two things:

1. **College wifi accounts**: an editor opens on `/etc/campus-login.conf`. Fill in the portal address and accounts, save and exit. Use `--skip internet` if this network has no login page.
2. **Headscale pre-auth key**: a hidden prompt at the end. Paste the key and press Enter (nothing is shown as you type).

### 4. Reboot and check

```bash
sudo reboot
```

```bash
sudo bash tools/check-server.sh
tailscale status
```

`tailscale status` should list this PC and the other club PCs. In the Headscale container, `headscale nodes list` should show it too. Then expire the pre-auth key you used (`headscale preauthkeys --help` lists the command).

## Install as a package (APT)

Instead of cloning, add the signed APT repository and install the `.deb`:

```bash
curl -fsSL https://elvinrodrigues.github.io/dual-mode-server/install.sh | sudo bash
sudo apt install dual-mode-server
```

Then run `sudo dual-mode-server --all --hostname flcpc1` (same options as `setup.sh`) or `sudo dual-mode-optimize --debian --all`. Installing the package changes nothing by itself. Update later with `sudo apt update && sudo apt upgrade`.

### Publishing a release (maintainer)

One-time setup:

1. Create a signing key with no passphrase: `gpg --quick-gen-key "dual-mode-server <you@example.com>" rsa4096 sign never`.
2. Add its private key as the repository secret `GPG_PRIVATE_KEY`: `gpg --armor --export-secret-keys <KEYID>`. Never commit it.
3. In GitHub, set Settings → Pages → Source to "GitHub Actions".

Per release: `git tag v0.1.0 && git push origin v0.1.0`. The workflow in `.github/workflows/release.yml` builds the `.deb`, attaches it to a GitHub release and republishes the repository. To build locally, run `packaging/build-deb.sh [VERSION]` (needs `dpkg-deb`) and `packaging/build-apt-repo.sh` (needs `apt-utils` and a GPG key).

## What `setup.sh` does

`setup.sh` runs the repo's scripts in order. Each step also works on its own.

| Step | What it runs |
| :--- | :--- |
| `optimize` | `optimize.sh --all`: SSH hardening, firewall, memory, disk, boot menu (see [Modules](#modules)). |
| `internet` | The `campus-login` module (captive-portal auto-login), then opens the accounts file for you to fill in. |
| `tools` | `tools/install-devtools.sh`: docker, node, pnpm, bun, curl, wget, zip, unzip, 7zip. Then `optimize.sh --only docker`, to harden the Docker that was just installed. |
| `headscale` | `tools/install-tailscale.sh` (Tailscale from its apt repository), then `tools/join-headscale.sh` (joins the club's Headscale network). |

| Option | Meaning |
| :--- | :--- |
| `--all` | Run every step. |
| `--only a,b` | Run only these steps, for example `--only tools,headscale`. |
| `--skip a,b` | Leave these steps out, for example `--skip internet`. |
| `--hostname NAME` | Name this PC gets on the Headscale network (default: its hostname). |
| `--key-file FILE` | Read the pre-auth key from a file instead of asking. |
| `--optimize-args "..."` | Extra options for `optimize.sh`, for example `"--allowed-nets 10.0.0.0/24"`. |
| `--dry-run` | Show the commands and change nothing. |

Running it again is safe. If a step fails, the script stops and prints how to continue.

### If something goes wrong

- **A step failed.** Fix the problem, then run the remaining steps, for example `sudo bash setup.sh --only tools,headscale --hostname flcpc1`.
- **The network blocks Tailscale's apt repository.** On a network that allows it, download the `.deb` from `pkgs.tailscale.com` onto a USB stick, then run `sudo bash tools/install-tailscale.sh --deb /path/to/file.deb` and re-run the `headscale` step. Tailscale is skipped when it is already installed.
- **`join-headscale.sh` says it cannot reach the Headscale server.** The network is blocking it. Open the server address in Firefox to see whether it loads.
- **You were locked out of SSH.** `fail2ban` bans an address for one hour after 5 wrong passwords. On the PC itself: `sudo fail2ban-client set sshd unbanip <address>`.
- **The PC was already logged in to another Tailscale network.** Run `sudo bash tools/join-headscale.sh --hostname flcpc1 --force` directly, which re-registers it.

### The scripts on their own

| Script | What it does | Options |
| :--- | :--- | :--- |
| `tools/install-devtools.sh` | Installs curl, wget, zip, unzip, 7zip, Docker (with compose), Node and npm from Debian's apt mirrors, then pnpm and bun with `npm install -g`. An existing Docker or Node is left alone (Debian's `docker.io` would replace Docker's own `docker-ce`). A fresh Node is Debian's own version, so it may be older than the latest release. | `--only a,b`, `--skip a,b` (items: `base`, `docker`, `node`, `pnpm`, `bun`) |
| `tools/install-tailscale.sh` | Installs the Tailscale client from its apt repository. Does nothing if it is already installed. | `--deb FILE` |
| `tools/join-headscale.sh` | Joins this PC to the Headscale network, checks the server is reachable first, adds a firewall rule for `tailscale0`. The key is read from `--key-file`, `$HEADSCALE_AUTHKEY`, or a hidden prompt, and is never written to the repo. | `--hostname`, `--key-file`, `--server`, `--force` |

After `tools/install-devtools.sh`, log out and back in so that your user can run `docker` without `sudo`.

## Only the optimize step

If you just want the server tuning and nothing else:

```bash
sudo bash optimize.sh --debian --all
sudo reboot
sudo bash tools/check-server.sh
```

### SSH keys

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
| `--open-web-ports` | Also allow ports 80, 443 and 3000:3999 through the firewall. |
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
| `grub` | "Headless Server Mode" boot entry, first and default; menu shows for 10 s. |
| `gui-toggle` | `gui-stop` / `gui-start` commands. |
| `firewall` | UFW: management ports only from trusted networks (web/dev ports opt-in). |

**Optional module** (not part of `--all`; run it by name):

| Module | What it does |
| :--- | :--- |
| `campus-login` | Keeps a captive-portal network (college or hostel wifi) logged in. Installs a timer that checks every 2 minutes and logs in only when the network is offline. |

```bash
sudo bash optimize.sh --debian --only campus-login
sudo campus-login edit      # enter the portal address and your accounts
sudo campus-login           # log in now
sudo campus-login status    # recent attempts
```

The portal address and accounts live in `/etc/campus-login.conf` (root-only, mode 600) and are never part of the repo. The script assumes a portal that accepts `POST <portal>/login.xml` (Cyberoam/Sophos style, usually port 8090) and decides success by checking internet access afterwards. Other portal types need a different login request. Keep accounts only on machines you control, and remove them from shared PCs when you are done:
`sudo rm /etc/campus-login.conf && sudo systemctl disable --now campus-login.timer`.

Every file that gets replaced is first copied to `<file>.bak.<timestamp>` (skipped if it already matches the latest backup). The script is safe to run more than once.

## Several PCs over Headscale

`setup.sh --all` already joins the PC (step `headscale`). To join one by hand, run `sudo bash tools/join-headscale.sh --hostname <name>`; it asks for a pre-auth key. Then give each one an alias in `~/.ssh/config` **on your laptop** (this file is personal, so keep real addresses and usernames out of the repo):

```
Host pc1
  HostName <headscale-ip-of-pc1>
Host pc2
  HostName <headscale-ip-of-pc2>
Host pc1 pc2
  User <your-user>
  IdentityFile ~/.ssh/id_ed25519
  ConnectTimeout 10
```

Find each IP with `tailscale status`. Install your key once per PC (it asks for that PC's password), then connect by alias:

```bash
ssh-copy-id pc1
ssh pc1
```

To see which PCs are online and have key login working, run `bash tools/check-pcs.sh` on the laptop (or `bash tools/check-pcs.sh pc1 pc2` for specific aliases). It changes nothing.

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
setup.sh           one command for a fresh PC (--all runs every step in order)
optimize.sh        the optimize entry point
lib/common.sh      helpers and machine detection
modules/           one file per module (campus-login is optional)
distros/debian.sh  package names, ZRAM, boot loader for Debian
tools/             check-server.sh (read-only health check), install-devtools.sh,
                   install-tailscale.sh, join-headscale.sh,
                   check-pcs.sh (laptop-side: which PCs are reachable)
docs/              analysis and notes
```

## Adding a distro

Copy `distros/debian.sh` to `distros/<name>.sh` and provide the same names: `SSH_SERVICE`, `ADMIN_GROUP`, `EARLYOOM_CONF`, `distro_update_index`, `distro_install_base`, `distro_install_cockpit`, `distro_install_xfce`, `distro_zram`, `distro_auto_updates` and `distro_grub_headless`. Test it before listing it as supported.

## License

MIT, see [LICENSE](LICENSE).
