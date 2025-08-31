#!/usr/bin/env bash
# freeze-strict.sh — Pwnagotchi "firmware mode" hard-freeze
# - Holds every currently installed package (so apt upgrade does nothing)
# - Leaves ONLY your allowlist (below) unheld so you can install/upgrade them
# - Makes apt a bit quieter (no recommends)
# - Prints an idempotent MOTD banner with clear instructions
# - Safe to re-run: idempotent holds + banner replace

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run as root."; exit 1; }

# --- Allowlist: tools you want to be able to install/upgrade normally ---
ALLOW_PKGS=(tmux htop fastfetch ncdu rclone)

echo "[*] Building package inventory …"
# 1) All installed packages
mapfile -t INSTALLED < <(dpkg-query -W -f='${Status} ${binary:Package}\n' \
  | awk '$1=="install" && $2=="ok" && $3=="installed"{print $4}' \
  | sort -u)

# 2) Allowlist set
ALLOW_SET="$(printf '%s\n' "${ALLOW_PKGS[@]}" | sort -u)"

# 3) Compute hold list = everything installed EXCEPT allowlist
TO_HOLD=()
for p in "${INSTALLED[@]}"; do
  if ! grep -qxF "$p" <<< "$ALLOW_SET"; then
    TO_HOLD+=("$p")
  fi
done

echo "[*] Holding ${#TO_HOLD[@]} packages (everything installed, except: ${ALLOW_PKGS[*]})"
# Chunk xargs to avoid "argument list too long"
if ((${#TO_HOLD[@]})); then
  printf '%s\0' "${TO_HOLD[@]}" | xargs -0 -r -n100 apt-mark hold >/dev/null
fi

# 4) Ensure allowlist is unheld (in case they were held previously)
if ((${#ALLOW_PKGS[@]})); then
  echo "[*] Ensuring allowlist is unheld: ${ALLOW_PKGS[*]}"
  printf '%s\0' "${ALLOW_PKGS[@]}" | xargs -0 -r -n20 apt-mark unhold >/dev/null || true
fi

# 5) Make upgrades conservative (no recommends to avoid surprise deps)
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99-no-recommends

# 6) Refresh apt metadata and show upgradable count
apt-get update -y || true
UPG_COUNT="$(apt list --upgradable 2>/dev/null | awk '/\[upgradable from:/{c++} END{print c+0}')"
echo "[*] Upgradable packages after freeze: ${UPG_COUNT}"

# --- MOTD: single, idempotent banner with markers ---
MOTD_FILE="/etc/motd"
BEGIN="#=== PWNAGOTCHI_FIRMWARE_BANNER BEGIN ==="
END="#=== PWNAGOTCHI_FIRMWARE_BANNER END ==="

# Remove previous marked banner (if present)
if grep -q "^$BEGIN" "$MOTD_FILE" 2>/dev/null; then
  sed -i "/^$BEGIN/,/^$END/d" "$MOTD_FILE"
fi

# Append fresh banner once
cat >> "$MOTD_FILE" <<'MOTD'
#=== PWNAGOTCHI_FIRMWARE_BANNER BEGIN ===
############################################################
#  PWNAGOTCHI FIRMWARE MODE (STRICT HOLD)
#  - All currently installed packages are on HOLD
#  - Allowed tools (not held): tmux htop fastfetch ncdu rclone
#  - `apt upgrade` should show 0 upgrades
#  - Allow a package:   sudo apt-mark unhold <pkg>
#  - Re-freeze it:      sudo apt-mark hold <pkg>
############################################################
#=== PWNAGOTCHI_FIRMWARE_BANNER END ===
MOTD

echo "[+] Strict freeze complete."
echo "    Tip: to add another tool later, run:  sudo apt-mark unhold <pkg> && sudo apt install <pkg> && sudo apt-mark hold <pkg>"
