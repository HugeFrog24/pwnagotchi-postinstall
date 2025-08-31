# 🐾 Pwnagotchi Postinstall Toolkit

Scripts to make a fresh **Pwnagotchi** installation less fragile and more fun.  
Out of the box, the community image works — but real-world use quickly runs into pain:

- **`apt upgrade` breaks things** → kernel/firmware mismatch, bettercap failing, display drivers gone.  
- **Display config scattered** → `ui.display.*` keys mixed across files.  
- **SSH over USB awkward** → requires manual `cmdline.txt` hacks.  
- **Bluetooth tether setup** → repetitive, error-prone edits.  

This repo collects my **postinstall hardening scripts** so you don’t have to re-learn the painful way.  
They are **idempotent** (safe to run multiple times) and talk back with little “gotchi chatter” so you see what happened.  

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

* Puts **all installed packages on hold** so `apt upgrade` does nothing.
* Leaves only your allow-list (`tmux htop fastfetch ncdu rclone`) free to install/upgrade.
* Updates `/etc/motd` with a big banner warning.

**Example:**

```bash
sudo ./postinstall-pwnagotchi-freeze.sh
```

---

### `postinstall-pwnagotchi-enforce-screen.sh`

Normalize **display configuration**:

* Comments out stray `ui.display.*` / `ui.invert` keys in any other `.toml`.
* Writes a clean `/etc/pwnagotchi/conf.d/display.toml` with your chosen settings.
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
  --ip 192.168.44.2
```

---

## ⚡ Usage Flow

1. Flash the image
2. Mount `boot/` → run `patch-pwnagotchi-usbnet.sh`
3. Boot → SSH in (`pi@10.0.0.2`)
4. Run `postinstall-pwnagotchi-freeze.sh`
5. Run `postinstall-pwnagotchi-enforce-screen.sh`
6. (Optional) run `postinstall-enforce-pwnagotchi-bt-tether.sh` for tethering

---

## 📝 License

MIT — use, share, modify freely. Contributions welcome.

---

## 🙃 Motivation

> “Feels like I’m reinstalling Windows every time I break it.
> These scripts turn it into a proper **embedded firmware flow**: boot, patch, done.
> Less fragility, more happy gotchi faces.”
