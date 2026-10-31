# Analysis of the Server Setup Kit

> [!NOTE]
> **Historical Document:** This analysis is a historical review of the initial prototype (`optimize-server.sh`). The findings below are fixed or mitigated in the current modular scripts, as noted:
> - **Finding 1 (Docker skips UFW):** Fixed in `modules/docker.sh` by binding published ports to `127.0.0.1` by default and capping container log sizes.
> - **Finding 2 (`vm.swappiness = 15`):** Fixed in `lib/common.sh` and `modules/memory.sh` by setting swappiness dynamically (150 for <=6 GB RAM, 100 otherwise) and `vm.page-cluster = 0`.
> - **Finding 3 (No OOM daemon):** Fixed in `distros/debian.sh` and `modules/memory.sh` by installing and enabling `earlyoom`.
> - **Finding 5 (`gui-stop` does not end XRDP sessions):** Not fixed. `gui-stop --all` stops the `xrdp` service, and the message in `modules/gui-toggle.sh` now says so; it does not end individual sessions.
> - **Finding 7 (Remote access hardening):** Partly fixed. `modules/firewall.sh` limits access to trusted subnets, and `modules/ssh.sh` adds `fail2ban` and no root login. Password login stays on until a key is installed, and XRDP and Cockpit still accept passwords from the trusted subnet.
> - **Finding 8 (sysctl tuning):** Fixed in `modules/memory.sh` by removing redundant `fs.file-max` and enabling BBR.
> - **Finding 9 (GRUB custom entry / `40_custom` overwrite):** Fixed in `lib/common.sh` (dynamic UUID detection) and `distros/debian.sh` (dedicated `/etc/grub.d/41_headless` and non-destructive removal of old entries from `40_custom`).
> - **Finding 10 (Disk tuning):** Fixed in `modules/disk.sh` (BFQ I/O scheduler udev rule, journal size cap, and SMART monitoring).
> - **Finding 11 (Cinnamon heavy over XRDP):** Mitigated only. `--rdp-desktop xfce` is available, but Cinnamon is still the default.
> - **Finding 12 (Missing backups / idempotency):** Mostly fixed. `backup()` in `lib/common.sh` creates timestamped copies and skips a file that matches its latest backup, so a repeat run adds at most one extra backup.

Review of `optimize-server.sh`, `PLAN.md`, `CONTEXT.md` and `README.md` for the Debian 13 dual-mode server (i3-2130, 4 GB RAM, 5900 RPM HDD).

**Short verdict:** The overall design works: one shared system, reachable over SSH, XRDP and Cockpit, with a headless boot option and a way to toggle the GUI. But some settings work against each other, some claims in the docs are wrong, and there is one serious security gap (Docker skips UFW). Fix the items marked 🔴 before you rely on this machine.

---

## 1. Summary of Findings

| # | Severity | Area | Finding |
| :- | :- | :- | :- |
| 1 | 🔴 High | Security | Docker-published ports skip UFW completely |
| 2 | 🔴 High | Memory | `vm.swappiness = 15` works against ZRAM and causes more HDD reads |
| 3 | 🔴 High | Stability | Nothing stops the machine from freezing when RAM runs out (no OOM daemon) |
| 4 | 🟠 Medium | XRDP | Logging in over XRDP as `student` while `student` is logged in at the local screen gives a black screen or an instant disconnect |
| 5 | 🟠 Medium | GUI toggle | `gui-stop` does not end XRDP sessions, so it does not free the RAM the docs say it does |
| 6 | 🟠 Medium | Docs | Cockpit cannot manage Docker containers (`cockpit-docker` was discontinued) |
| 7 | 🟠 Medium | Security | SSH, XRDP and Cockpit accept passwords from the whole LAN, using a `sudo` + `docker` account |
| 8 | 🟡 Low | sysctl | `fs.file-max = 2097152` *lowers* the kernel default; `somaxconn = 4096` is already the default |
| 9 | 🟡 Low | GRUB | The custom entry hardcodes the UUID and `/vmlinuz`, assumes no separate `/boot`, and overwrites `40_custom` |
| 10 | 🟡 Low | Disk | `noatime` gains little over the default `relatime`; the I/O scheduler and SMART monitoring matter more |
| 11 | 🟡 Low | XRDP | Full Cinnamon over XRDP runs in software rendering and is heavy for 4 GB |
| 12 | 🟡 Low | Script | Not idempotent (overwrites files without a backup), hides sysctl errors, and the UUID is not portable |

---

## 2. Detailed Findings

### 🔴 1. Docker bypasses UFW

Docker writes its own iptables rules (the `DOCKER` / `DOCKER-USER` chains), and those rules are checked **before** UFW's. A container started with `-p 5432:5432` (Postgres), `-p 6379:6379` (Redis) or `-p 27017:27017` (Mongo) can be reached by everyone on `<your-subnet>`, even with `ufw default deny incoming` and no matching allow rule.

On a shared campus/office LAN, this is the biggest risk in the whole setup.

**Fix (pick one):**
- Bind container ports to localhost unless they need to be public: `-p 127.0.0.1:5432:5432` (in compose: `"127.0.0.1:5432:5432"`).
- Or make that the default for every container in `/etc/docker/daemon.json`:
  ```json
  { "ip": "127.0.0.1" }
  ```
  Then publish public ports on purpose with `-p 0.0.0.0:80:80`.
- Or install [`ufw-docker`](https://github.com/chaifeng/ufw-docker), which makes UFW rules apply to containers.

### 🔴 2. `vm.swappiness = 15` works against ZRAM

The script sets low swappiness so that the system "prioritizes RAM over swap". That logic fits **disk** swap. With ZRAM, swapping is cheap (it is compression in RAM), and low swappiness pushes the kernel to drop **page cache** (cached file data) instead. On a 5900 RPM disk, that dropped cache has to be read back from the HDD, which is the very thrashing ZRAM was meant to stop.

**Fix**, in `/etc/sysctl.d/99-server-optimization.conf`:
```ini
vm.swappiness = 150        # kernel 5.8+ accepts 0-200; >100 favours swapping anon pages to zram over dropping file cache
vm.page-cluster = 0        # zram has no seek cost; read-ahead of swap pages is wasted work
vm.watermark_scale_factor = 125
```
Keep the disk swap partition as a low-priority fallback (ZRAM is set to priority 100, and disk swap defaults to −2, which is correct).

Also: the claim of "~5.5 GB usable memory" is optimistic. ZRAM is sized at 50% of RAM (≈1.85 GB uncompressed). With typical 2.5–3:1 compression it holds about 1.85 GB of pages in about 0.6–0.75 GB of RAM, so you gain roughly **+1.1–1.3 GB effective**: about 4.8–5 GB in practice.

### 🔴 3. No protection against freezes when RAM runs out

With 4 GB RAM, Docker, a GUI and Node/Bun dev servers, you will run out of memory sooner or later. The kernel's own OOM killer reacts very late. Before it acts, the system can spend minutes thrashing the HDD (re-reading executables and libraries) and look frozen. ZRAM delays this but does not prevent it.

**Fix:** install `earlyoom` (simple and light) or turn on `systemd-oomd`:
```bash
apt install -y earlyoom
# /etc/default/earlyoom
EARLYOOM_ARGS="-m 5 -s 10 --avoid '(^|/)(sshd|systemd|Xorg|xrdp|xrdp-sesman|dockerd|containerd)$' --prefer '(^|/)(node|bun|chrome|chromium|code)$'"
systemctl enable --now earlyoom
```

Also cap memory for containers (`mem_limit:` in compose, `--memory=512m`), so that one runaway container cannot take down both users' sessions.

### 🟠 4. XRDP + local login as the same user

Your requirement (Person A on XRDP, Person B on SSH, both as `student`) **works**: SSH and XRDP sessions for the same user can run side by side.

It breaks when `student` is **also logged in at the physical screen** (LightDM → Cinnamon). An XRDP login as `student` then usually shows a black screen or disconnects at once, because both Cinnamon sessions fight over the same user D-Bus/systemd session. Two XRDP sessions as `student` at once have the same problem.

**Options:**
- Simplest: log out at the local screen (or run `gui-stop`) before connecting over XRDP. The machine is a server, so this is usually fine.
- Or, if you want more than one person on the GUI: create a second account (e.g. `dev2`), add both accounts to a shared group, and work in a shared directory:
  ```bash
  groupadd devs && usermod -aG devs student && usermod -aG devs dev2 && usermod -aG docker dev2
  mkdir -p /srv/projects && chgrp devs /srv/projects && chmod 2775 /srv/projects
  ```
  This still meets the "no isolation" requirement: same kernel, same files, same Docker daemon, same ports, same RAM. Only the login session differs, which is what XRDP needs.

### 🟠 5. `gui-stop` does not free what the docs say

`systemctl stop lightdm` ends only the **local** display session. XRDP sessions are started by `xrdp-sesman`, not LightDM, so they keep running and keep their RAM. Also:
- In "Headless Server Mode" (`multi-user.target`), `xrdp` is still enabled and starts anyway. That is useful (remote GUI on demand), but say so in the docs, because the RAM is used as soon as someone connects over RDP.
- "Frees ~1.5 GB" is a guess. A typical idle Cinnamon session uses about 0.6–1.0 GB. Measure it with `free -h` before and after.
- `gui-stop` ends the local session with no warning, so anything unsaved is lost.

**Improved toggles:**
```bash
# /usr/local/bin/gui-stop
#!/bin/bash
set -e
read -rp "This ends the local desktop (unsaved work is lost). Continue? [y/N] " a
[[ "$a" =~ ^[Yy]$ ]] || exit 0
sudo systemctl isolate multi-user.target   # stops lightdm and other graphical-only units
if [[ "${1:-}" == "--all" ]]; then
    sudo systemctl stop xrdp xrdp-sesman    # also end remote desktop sessions
fi
free -h

# /usr/local/bin/gui-start
#!/bin/bash
sudo systemctl start xrdp 2>/dev/null || true
sudo systemctl isolate graphical.target
```

### 🟠 6. Cockpit and Docker

`PLAN.md` and `CONTEXT.md` say you can "inspect Docker containers" in Cockpit. Upstream dropped the `cockpit-docker` plugin. Debian 13 ships only `cockpit-podman`, which shows Podman containers, not Docker's. In Cockpit you can still use the terminal (`docker ps`), but there is no container page.

**Options:** run [Portainer CE](https://www.portainer.io/) (closest to a Hostinger panel, about 30–60 MB RAM) or [Dozzle](https://dozzle.dev/) (log viewer only, about 10 MB), and bind each one to localhost or a firewalled port.

Also: `apt install cockpit` pulls in recommended packages, including **PackageKit**, which can keep 100–200 MB resident. On 4 GB, consider:
```bash
apt install -y --no-install-recommends cockpit cockpit-system cockpit-networkmanager cockpit-storaged
```

### 🟠 7. Remote access hardening

`student` is in `sudo` and `docker` (and `docker` membership is root-equivalent). All three ways in (SSH 22, RDP 3389, Cockpit 9090) accept a password from anyone on the LAN.

Recommended:
```bash
# Limit management ports to your subnet (or to specific IPs)
ufw delete allow 22/tcp;   ufw allow from <your-subnet> to any port 22   proto tcp
ufw delete allow 3389/tcp; ufw allow from <your-subnet> to any port 3389 proto tcp
ufw delete allow 9090/tcp; ufw allow from <your-subnet> to any port 9090 proto tcp

# SSH: keys only, after copying your key (ssh-copy-id student@<server-ip>)
cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin no
EOF
systemctl reload ssh

apt install -y fail2ban   # protects sshd by default
```
For access from **outside** the LAN (the real "VPS" experience), use **Tailscale** or a **Cloudflare Tunnel** instead of port-forwarding 22, 3389 or 9090 to the internet. Do not expose RDP to the internet directly.

### 🟡 8. sysctl notes

| Setting | Comment |
| :- | :- |
| `fs.file-max = 2097152` | On kernel 6.12 the default is already `9223372036854775807`, so this line **lowers** it (harmlessly). Remove it. The limit that matters is per-process `nofile` (`ulimit -n`, systemd `LimitNOFILE`). |
| `net.core.somaxconn = 4096` | Already the default since kernel 5.4. It does nothing, but it is harmless. |
| `tcp_tw_reuse = 1` | Fine (the default `2` covers only loopback). |
| `ip_local_port_range = 10240 65535` | Fine. It does not overlap 3000–3999. |
| `dirty_background_ratio 5 / dirty_ratio 10` | Good for an HDD (≈185 MB / ≈370 MB on 3.7 GB). |
| BBR | `PLAN.md` mentions BBR but the script never turns it on. Add `net.core.default_qdisc = fq` and `net.ipv4.tcp_congestion_control = bbr`. The gain on a LAN is small, but the docs then match the script. |

### 🟡 9. GRUB custom entry

It works on a standard Debian install (`/vmlinuz` and `/initrd.img` symlinks in `/`, no separate `/boot`), but it is fragile:
- It hardcodes `ROOT_UUID`, so the script breaks on any other machine.
- It boots `/vmlinuz` (the newest kernel) with no fallback, and it drops `GRUB_CMDLINE_LINUX_DEFAULT` (any `resume=`, `mitigations=` and similar options are lost).
- `cat > /etc/grub.d/40_custom` erases any entries already in that file.
- It assumes an MBR disk (`part_msdos`).

**A simpler, sturdier option:** let GRUB generate the entries, and make headless the **default** with GUI on demand, or the other way round:
```bash
systemctl set-default multi-user.target    # boot headless; run gui-start when you want the desktop
# or: systemctl set-default graphical.target
```
If you keep the menu entry, at least set `ROOT_UUID="$(findmnt -no UUID /)"` and back up `40_custom` before overwriting it.

### 🟡 10. Disk: what actually helps on a 5900 RPM drive

- `noatime`: Debian already mounts with `relatime`, which skips most atime writes. `noatime` is a small extra gain, not a "drastic" cut. It is fine to keep.
- **I/O scheduler:** on a single HDD shared by a desktop and Docker, `bfq` keeps interactive sessions responsive under heavy writes:
  ```bash
  echo 'ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"' \
    > /etc/udev/rules.d/60-iosched.rules
  ```
- **Drive health:** the ST3500414CS is a consumer DVR drive, and probably an old one. Install `smartmontools`, check `smartctl -a /dev/sda` (Reallocated / Pending sectors), and keep backups of `/home/student` and Docker volumes elsewhere.
- **Cap the journal:** set `SystemMaxUse=200M` in `/etc/systemd/journald.conf`.
- **Docker logs:** without a limit, container logs grow forever. In `/etc/docker/daemon.json`:
  ```json
  { "log-driver": "local", "log-opts": { "max-size": "10m", "max-file": "3" } }
  ```

### 🟡 11. Cinnamon over XRDP

XRDP has no GPU acceleration, so Cinnamon falls back to software rendering, which is CPU-heavy on a 2-core Sandy Bridge and uses about 0.7–1 GB per session.
- Use the 2D session: `echo "cinnamon-session --session cinnamon2d" > ~/.xsession`
- Or, for remote sessions, a much lighter desktop such as **XFCE** (about 300–400 MB): install `xfce4` and set `~/.xsession` to `startxfce4`. The local screen can stay on Cinnamon.

### 🟡 12. Script robustness

- `ROOT_UUID` is hardcoded → use `findmnt -no UUID /`.
- The script overwrites `~/.xsession`, `/etc/grub.d/40_custom`, `/etc/default/zramswap` and the polkit rule without a backup. Add `cp -a "$f" "$f.bak.$(date +%s)"` before each write.
- `sysctl --system >/dev/null 2>&1` hides typos. Let the errors print.
- `usermod -aG docker` only takes effect after the user logs in again. Print a note saying so.
- Remove services this server does not need, to free RAM and CPU: `systemctl disable --now cups cups-browsed bluetooth ModemManager avahi-daemon` (only the ones you don't use).
- The governor: the i3-2130 has no Turbo Boost and runs under `intel_pstate`. Its `powersave` mode is already dynamic and ramps up fast. `performance` gives very little gain and keeps the chip at full clock 24/7. It is fine to keep, but it is optional.
- Add `unattended-upgrades` so a machine that runs 24/7 gets security patches.

---

## 3. What Is Already Good

- ZRAM with `zstd` at priority 100 above disk swap: the right idea for this hardware.
- Dirty-page ratios tuned for an HDD.
- The polkit rule for colord/PackageKit prompts under XRDP.
- UFW with default-deny (once the Docker gap is closed).
- Sleep/suspend targets masked for a machine that runs 24/7.
- The "no isolation" design is consistent: one kernel, one Docker daemon, one filesystem.

---

## 4. Recommended Change Order

1. Close the Docker/UFW gap (`daemon.json` `"ip": "127.0.0.1"` + log limits) → `systemctl restart docker`
2. Fix swappiness for ZRAM (`150`, `page-cluster = 0`) → `sysctl --system`
3. Install and turn on `earlyoom`
4. Limit 22/3389/9090 to your subnet; SSH keys + `fail2ban`
5. Update `gui-stop` / `gui-start`; document the XRDP same-user limitation
6. Correct `PLAN.md` / `CONTEXT.md`: Cockpit cannot manage Docker, the RAM figures, BBR
7. Optional: `bfq` scheduler, `smartmontools`, XFCE for RDP, remove unused services

**Check the results after the changes:**
```bash
free -h; zramctl; swapon --show
sysctl vm.swappiness vm.page-cluster
cat /sys/block/sda/queue/scheduler
sudo ufw status numbered
sudo iptables -L DOCKER-USER -n
docker run --rm -d -p 8080:80 nginx   # from ANOTHER machine: curl http://<server-ip>:8080 should FAIL after step 1
systemctl status earlyoom
```
