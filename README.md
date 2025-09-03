# 🐾 Pwnagotchi Postinstall Toolkit

<p align="center">
  <img src="logo.svg" alt="Pwnagotchi Postinstall Toolkit logo" width="200"/>
</p>

[![ShellCheck](https://github.com/HugeFrog24/pwnagotchi-postinstall/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/HugeFrog24/pwnagotchi-postinstall/actions/workflows/shellcheck.yml)

Scripts to streamline a fresh Pwnagotchi installation.

I built this after nuking my gotchi too many times.  
These scripts saved my sanity - now they can save yours.  

This toolkit was born while setting up a PiSugar 3 + Raspberry Pi Zero 2W Pwnagotchi for daily use.  
After several frustrating soft bricks and reinstalls, I automated the fixes I kept repeating.  
Hope this saves you the same headaches and helps your gotchi grow up healthy and happy.

---

## 🚨 Why this exists

Out of the box, the community image works - but real-world use quickly runs into pain:

- **`apt upgrade` breaks things** → kernel/firmware mismatch, bettercap failing, display drivers gone.
- **Display config scattered** → `ui.display.*` keys mixed across files.
- **SSH over USB awkward** → requires manual `cmdline.txt` hacks.
- **Bluetooth tether setup** → repetitive, error-prone edits.

### Just use `pwnagotchi --wizard`, they said…
Sure, but the [wizard](https://github.com/jayofelony/pwnagotchi/blob/noai/pwnagotchi/cli.py) is fully interactive, needs hand-holding, can't be scripted, and nukes your config every time you re-run it. It overwrites config.toml, ignores conf.d/*, and restarts the service mid-edit. There's zero input validation, even bugs like missing parentheses (`.lower` without `()`) sneak through. Fine for one-time setup on your desk - not for headless use, automation, or mass deployment.

This repo collects postinstall hardening scripts to automate those fixes.
They are idempotent (safe to run multiple times) and talk back with little gotchi chatter so you see what happened.

---

## 📂 Scripts

### `patch-pwnagotchi-usbnet.sh`
Patch the **boot partition** before first boot to enable SSH-over-USB.

- Ensures `modules-load=dwc2,g_ether`
- Adds a static or DHCP IP stanza (`10.0.0.2 <-> 10.0.0.1` by default)
- Drops `ssh` flag file so SSH is enabled immediately  

**Example:**
```bash
./patch-pwnagotchi-usbnet.sh /run/media/$USER/bootfs static 10.0.0.2 10.0.0.1 255.255.255.0 pwnagotchi
````

---

### `postinstall-pwnagotchi-freeze.sh`

Lock down the system into **“firmware mode”**:

* Puts all installed packages on hold so `apt upgrade` does nothing.
* Leaves only your allow-list (`tmux htop ncdu rclone`) free to install/upgrade.
* Updates `/etc/motd` with a big banner warning.

**Example:**

```bash
sudo ./postinstall-pwnagotchi-freeze.sh
```

---

### `postinstall-pwnagotchi-enforce-screen.sh`

Normalize **display configuration**:

* Comments out stray `ui.display.*` / `ui.invert` keys in any other `.toml`.
* Writes a clean `/etc/pwnagotchi/conf.d/10-display.toml` with your chosen settings.
* Idempotent: only changes if needed, shows restart hint if something changed.

**Example:**

```bash
sudo ./postinstall-pwnagotchi-enforce-screen.sh
```

---

### `postinstall-enforce-pwnagotchi-bt-tether.sh`

Helper for **Bluetooth tethering** setup:

* Takes phone name, type (`android|ios`), MAC and tether IP.
* Moves stray `main.plugins.bt-tether.*` keys into `conf.d/20-bt-tether.toml`.
* Adds sanity hints if your IP doesn’t match typical Android/iOS ranges.

**Example:**

```bash
sudo ./postinstall-enforce-pwnagotchi-bt-tether.sh \
  --name "OnePlus 13" \
  --type android \
  --mac 7C:F0:E5:48:F8:2E \
  --ip 192.168.44.44
```

---

### `install-fastfetch.sh`

Installer for `fastfetch`, the friendly system info fetch tool.

* Fetches the latest `.deb` release for your system architecture
* Works on Debian-based systems (e.g. Pwnagotchi OS, Raspberry Pi OS)
* Skips if already installed
* Fails gracefully on unsupported systems

**Example:**
```bash
./install-fastfetch.sh
```

---

## 🎯 Nice-to-Haves

You can toggle between manual mode and auto mode using the **action button** on the PiSugar board - but you'll need a small shell script to check the current mode, and switch to the opposite accordingly.

### How to set it up:

1. **Copy the toggle script**:
   ```bash
   sudo cp ./utils/pisugar/toggle_mode.sh /home/pi/toggle_mode.sh
   sudo chmod +x /home/pi/toggle_mode.sh
   ```

2. **Set it in the PiSugar web dashboard**:
   Go to: http://192.168.44.44:8421/#/ → under **Double Tap** or **Long Press**, set the action to:
   ```bash
   sudo /home/pi/toggle_mode.sh
   ```
   Click **Confirm**.

### How it works:
* The script checks for the presence of the `.pwnagotchi-manu` file.
* If it exists, it switches to auto.
* If it doesn't exist, it assumes auto mode and switches to manual.
* Then it restarts the Pwnagotchi service to apply the mode change.

---

## ⚡ Usage Flow

1. Clone me:
   ```bash
   git clone https://github.com/YOURNAME/pwnagotchi-postinstall.git && cd pwnagotchi-postinstall
   ```
1. Flash image
2. Mount `boot/` → run `patch-pwnagotchi-usbnet.sh`
3. Boot → SSH in (`pi@10.0.0.2`)
4. Run `postinstall-pwnagotchi-freeze.sh`
5. Run `postinstall-pwnagotchi-enforce-screen.sh`

**Optional:**  
1. Run `postinstall-enforce-pwnagotchi-bt-tether.sh` for tethering
2. Run `install-fastfetch.sh` to install fastfetch

---

## Useful Links

* **Official Website** (pwnagotchi.org):
   * https://pwnagotchi.org/
   * the core Pwnagotchi documentation, download links, hardware recommendations, plugin guides, BT-tethering walkthroughs, and much more.
* **Main GitHub Repo** (jayofelony/pwnagotchi):
   * https://github.com/jayofelony/pwnagotchi
   * the source code, development tracker, plugin ecosystem, and pull request hub for the project.
* **Community Hub** (r/pwnagotchi):
   * https://www.reddit.com/r/pwnagotchi/
   * active Reddit community where users share setups, custom scripts, issues, and creative mods.
* **My Hardware Kit**:
   * https://www.pisugar.com/products/pwnagotchi-complete-pack-pi02w-pisugar3-eink-case
   * the full Pi Zero 2 W + PiSugar3 + e-ink + case bundle - works great out of the box (no sponsor).
* **Plugin Collection by wpa-2**:
   * https://github.com/wpa-2/Pwnagotchi-Plugins
   * a curated repo of community-made plugins and enhancements.

---

## 📝 License

MIT - use, share, modify freely. Contributions welcome.

---

## 🙃 Closing note

Less gotchas, more gotchis.  
Because every fresh flash should feel like a win - not a fragile science project.
From one PiSugar 3 + Zero 2W setup to yours: happy hacking, trainer!
