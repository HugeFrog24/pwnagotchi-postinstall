#!/usr/bin/env bash
set -euo pipefail

# Load shared environment detection
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/environment-detection.sh"

# 🛡️ Self-protection: don't run on the gotchi itself!
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE_MODE=true
  shift
fi

ensure_not_on_pwnagotchi "$0" "$FORCE_MODE"

# Handle -h / --help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage:
  $0 [--force] /path/to/bootfs [mode] [pi_ip] [host_ip] [netmask] [hostname]

Examples:
  $0 /run/media/\$USER/bootfs static 10.0.0.2 10.0.0.1 255.255.255.0 pwnagotchi
  $0 /run/media/\$USER/bootfs dhcp "" "" "" pwnagotchi

Arguments:
  --force           Skip environment detection (dangerous!)
  /path/to/bootfs   Path to the mounted FAT32 boot partition (after flashing image)
  mode              "static" or "dhcp" (default: static)
  pi_ip             Static IP of the Pi (default: 10.0.0.2)
  host_ip           IP of the host (default: 10.0.0.1)
  netmask           Netmask (default: 255.255.255.0)
  hostname          Hostname to embed in boot args (default: pwnagotchi)

What it does:
  ✓ Adds dwc2 + g_ether to modules-load
  ✓ Adds IP config to cmdline.txt
  ✓ Ensures dtoverlay=dwc2 in config.txt
  ✓ Enables SSH by creating /boot/ssh

💡 Run this script *before* first boot.
EOF
  exit 0
fi

# Defaults
BOOT="${1:-}"
MODE="${2:-static}"           # static | dhcp
PI_IP="${3:-10.0.0.2}"
HOST_IP="${4:-10.0.0.1}"
NETMASK="${5:-255.255.255.0}"
HN="${6:-pwnagotchi}"

if [[ -z "$BOOT" || ! -d "$BOOT" ]]; then
  echo "ERROR: Provide path to the mounted FAT boot partition (e.g. /run/media/\$USER/bootfs)"; exit 1
fi

CMD="${BOOT%/}/cmdline.txt"
CFG="${BOOT%/}/config.txt"
SSH_FLAG="${BOOT%/}/ssh"
ts() { date +%Y%m%d-%H%M%S; }

[[ -f "$CMD" ]] || { echo "ERROR: $CMD not found"; exit 1; }
[[ -f "$CFG" ]] || { echo "ERROR: $CFG not found"; exit 1; }

cp -a "$CMD" "${CMD}.bak.$(ts)"
cp -a "$CFG" "${CFG}.bak.$(ts)"

# Read single-line cmdline
line="$(tr -d '\n' < "$CMD")"

# 1) Ensure modules-load includes dwc2,g_ether
if grep -qE '\bmodules-load=' <<< "$line"; then
  # Normalize: extract list, ensure both present
  current="$(sed -E 's/.*\bmodules-load=([^ ]*).*/\1/' <<< "$line")"
  IFS=',' read -r -a mods <<< "$current"
  want=(dwc2 g_ether)
  for m in "${want[@]}"; do
    if ! printf '%s\n' "${mods[@]}" | grep -qx "$m"; then
      current="${current},${m}"
    fi
  done
  line="$(sed -E "s/\bmodules-load=[^ ]*/modules-load=${current}/" <<< "$line")"
else
  line="${line} modules-load=dwc2,g_ether"
fi

# 2) Ensure IP stanza (static or dhcp)
if [[ "$MODE" == "dhcp" ]]; then
  ipval="ip=:::::usb0:dhcp"
else
  # static
  ipval="ip=${PI_IP}::${HOST_IP}:${NETMASK}:${HN}:usb0:off"
fi

if grep -qE '\bip=[^ ]+' <<< "$line"; then
  line="$(sed -E "s/\bip=[^ ]+/${ipval}/" <<< "$line")"
else
  line="${line} ${ipval}"
fi

# 3) Write back (single line)
printf '%s\n' "$line" > "$CMD"

# 4) Ensure dtoverlay=dwc2 in config.txt (once)
if ! grep -qE '^\s*dtoverlay=dwc2(\b|,|$)' "$CFG"; then
  printf '\n# USB gadget for ssh-over-USB\n%s\n' "dtoverlay=dwc2" >> "$CFG"
fi

# 5) Enable SSH
: > "$SSH_FLAG"

echo -e "\e[32mPatched:\e[0m"
echo -e "\e[32m - $(basename "$CMD") (modules-load + ${MODE^^} ip)\e[0m"
echo -e "\e[32m - $(basename "$CFG") (dtoverlay=dwc2 ensured)\e[0m"
echo -e "\e[32m - created $(basename "$SSH_FLAG") to enable SSH\e[0m"
