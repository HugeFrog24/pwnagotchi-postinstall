#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./patch-pwnagotchi-usbnet.sh /path/to/bootfs [mode] [pi_ip] [host_ip] [netmask] [hostname]
# Examples:
#   ./patch-pwnagotchi-usbnet.sh /run/media/$USER/bootfs static 10.0.0.2 10.0.0.1 255.255.255.0 pwnagotchi
#   ./patch-pwnagotchi-usbnet.sh /run/media/$USER/bootfs dhcp "" "" "" pwnagotchi

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

echo "Patched:"
echo " - $(basename "$CMD") (modules-load + ${MODE^^} ip)"
echo " - $(basename "$CFG") (dtoverlay=dwc2 ensured)"
echo " - created $(basename "$SSH_FLAG") to enable SSH"
