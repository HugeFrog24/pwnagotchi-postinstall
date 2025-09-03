#!/usr/bin/env bash
# postinstall-enforce-pwnagotchi-bt-tether.sh
# Enforce Pwnagotchi BT-tether config via templates (idempotent, change-aware)

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Template filenames (defined early for help text)
TEMPLATE_BASE_NAME="20-bt-tether.toml"
TEMPLATE_OVERRIDE_NAME="99-bt-tether.override.toml"

# --- help check FIRST (before root check) ---
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage:
  sudo ./$(basename "$0") \
    [--force] \
    [--name "<phone name>"] \
    [--type <android|ios>] \
    [--mac AA:BB:CC:DD:EE:FF] \
    [--ip x.y.z.w]

How it decides what to write:
  1) If templates/${TEMPLATE_OVERRIDE_NAME} exists, it is used as-is (preferred).
  2) Otherwise, templates/${TEMPLATE_BASE_NAME} is loaded and the values for
     phone-name, phone, mac, and ip are filled from CLI arguments.
     All four fields are REQUIRED; the script fails if any end up empty.

Environment:
  - Automatically detects Pwnagotchi devices (Raspberry Pi + pwnagotchi indicators)
  - Use --force to bypass detection and run on any system

Tips:
  - Create templates/${TEMPLATE_OVERRIDE_NAME} once with your real values and
    skip CLI flags forever (keep it .gitignored).

Example:
  sudo ./$(basename "$0") \
    --name "OnePlus 13" --type android \
    --mac 7C:F0:E5:48:F8:2E --ip 192.168.44.44
EOF
  exit 0
fi

# NOW check for root privileges
[[ $EUID -eq 0 ]] || { echo "(╥☁╥ ) run me as root pls" >&2; exit 1; }

# Load shared libraries only after confirming we need them
source "${SCRIPT_DIR}/lib/environment-detection.sh"
source "${SCRIPT_DIR}/lib/config-utils.sh"

# 🛡️ Environment detection: ensure we're on a Pwnagotchi device
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE_MODE=true
  shift
fi

ensure_on_pwnagotchi "$0" "$FORCE_MODE"

CONF_DIR="/etc/pwnagotchi/conf.d"
TS="$(date +%Y%m%d-%H%M%S)"

# Templates (base is required; override is optional and ignored by git)
TEMPLATE_BASE="${SCRIPT_DIR}/templates/${TEMPLATE_BASE_NAME}"
TEMPLATE_OVERRIDE="${SCRIPT_DIR}/templates/${TEMPLATE_OVERRIDE_NAME}"
OUT_FILE="${CONF_DIR}/${TEMPLATE_BASE_NAME}"

PHONE_NAME=""
PHONE_TYPE=""
PHONE_MAC=""
PHONE_IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) PHONE_NAME="${2:-}"; shift 2 ;;
    --type) PHONE_TYPE="${2:-}"; shift 2 ;;
    --mac)  PHONE_MAC="${2:-}";  shift 2 ;;
    --ip)   PHONE_IP="${2:-}";   shift 2 ;;
    *) echo "(•_•?) unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$CONF_DIR"

# --- helpers ---
escape_sed() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
get_toml_val() {
  local key="$1" file="$2"
  # extract value inside quotes: key = "value"
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" \
    | sed -E 's/^[^=]*=\s*"([^"]*)".*$/\1/' \
    | head -n1 | trim
}

# --- build desired config from templates ---
DESIRED=""
SOURCE=""

if [[ -f "$TEMPLATE_OVERRIDE" ]]; then
  DESIRED="$(cat "$TEMPLATE_OVERRIDE")"
  SOURCE="override"
else
  [[ -f "$TEMPLATE_BASE" ]] || { echo "Missing template: $TEMPLATE_BASE"; exit 1; }
  tmp="$(cat "$TEMPLATE_BASE")"

  # Fill from CLI (required)
  for pair in \
    "main\\.plugins\\.bt-tether\\.phone-name|$PHONE_NAME" \
    "main\\.plugins\\.bt-tether\\.phone|$PHONE_TYPE" \
    "main\\.plugins\\.bt-tether\\.mac|$PHONE_MAC" \
    "main\\.plugins\\.bt-tether\\.ip|$PHONE_IP"
  do
    key="${pair%%|*}"; val="${pair#*|}"
    if [[ -z "$val" ]]; then
      echo "(☉_☉ ) missing required flag for ${key##*.} (see --help)"; exit 3
    fi
    tmp="$(sed -E \
      "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\\1\"$(escape_sed "$val")\"|g" \
      <<< "$tmp")"
  done

  DESIRED="$tmp"
  SOURCE="template+cli"
fi

# --- validate resulting config (no empties, correct formats) ---
tmpfile="$(mktemp)"; trap 'rm -f "$tmpfile"' EXIT
printf '%s\n' "$DESIRED" > "$tmpfile"

VAL_NAME="$(get_toml_val 'main\.plugins\.bt-tether\.phone-name' "$tmpfile")"
VAL_TYPE="$(get_toml_val 'main\.plugins\.bt-tether\.phone' "$tmpfile")"
VAL_MAC="$(get_toml_val  'main\.plugins\.bt-tether\.mac' "$tmpfile")"
VAL_IP="$(get_toml_val   'main\.plugins\.bt-tether\.ip' "$tmpfile")"

if [[ -z "$VAL_NAME" || -z "$VAL_TYPE" || -z "$VAL_MAC" || -z "$VAL_IP" ]]; then
  echo "(╥☁╥ ) the resulting config has empty fields. Fix your ${SOURCE} input." >&2
  exit 4
fi

# Convert to lowercase for case-insensitive comparison
VAL_TYPE_LOWER="${VAL_TYPE,,}"
case "$VAL_TYPE_LOWER" in
  android) VAL_TYPE="android" ;;
  ios) VAL_TYPE="ios" ;;
  *) echo "(≖__≖) phone type must be 'android' or 'ios' (got: $VAL_TYPE)"; exit 5 ;;
esac

valid_mac='^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
valid_ip='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
if ! [[ "$VAL_MAC" =~ $valid_mac ]]; then
  echo "(╥☁╥ ) invalid MAC: '$VAL_MAC'"; exit 6
fi
if ! [[ "$VAL_IP" =~ $valid_ip ]]; then
  echo "(╥☁╥ ) invalid IP: '$VAL_IP'"; exit 7
fi

echo "(◕‿◕) using source: ${SOURCE}"

# Sanity hints (non-fatal)
if [[ "$VAL_TYPE" == "android" && "$VAL_IP" != 192.168.44.* ]]; then
  echo "(•‿‿•) hint: Android ICS usually sits at 192.168.44.x; you set $VAL_IP"
fi
if [[ "$VAL_TYPE" == "ios" && "$VAL_IP" != 172.20.10.* ]]; then
  echo "(•‿‿•) hint: iOS tether usually sits at 172.20.10.x; you set $VAL_IP"
fi

# --- de-stray managed keys from other TOMLs ---
echo "(◕‿◕) scanning $CONF_DIR for messy bt-tether configs …"

KEY_RE='main\.plugins\.bt-tether\.(enabled|phone-name|phone|mac|ip)'
CLEAN_COUNT=0
KEY_COUNT=0
CHANGED=0

for f in "$CONF_DIR"/*.toml; do
  [[ -f "$f" ]] || continue
  [[ "$f" == "$OUT_FILE" ]] && continue
  if grep -Eq "^[[:space:]]*${KEY_RE}[[:space:]]*=" "$f"; then
    MOVED=$(grep -Ec "^[[:space:]]*${KEY_RE}[[:space:]]*=" "$f" || true)
    echo "(☉_☉ ) trainer, $(basename "$f") has $MOVED stray bt-tether key(s)!"
    echo "        → backup: ${f}.bak.${TS}"
    cp -a "$f" "${f}.bak.${TS}"
    sed -E -i "/^[[:space:]]*${KEY_RE}[[:space:]]*=/ s|^|# gotchi moved: |" "$f"
    echo "        → moved out; they belong in ${TEMPLATE_BASE_NAME} ♥"
    CLEAN_COUNT=$((CLEAN_COUNT+1))
    KEY_COUNT=$((KEY_COUNT+MOVED))
    CHANGED=1
  fi
done

# --- write only if different ---
if [[ -f "$OUT_FILE" ]]; then
  CURRENT="$(sed -e 's/[[:space:]]*$//' "$OUT_FILE")"
else
  CURRENT=""
fi
NORMALIZED_DESIRED="$(printf '%s\n' "$DESIRED" | sed -e 's/[[:space:]]*$//')"

if [[ "$CURRENT" != "$NORMALIZED_DESIRED" ]]; then
  echo "(✜‿‿✜) writing my perfect bt-tether config to $(basename "$OUT_FILE") …"
  [[ -f "$OUT_FILE" ]] && cp -a "$OUT_FILE" "${OUT_FILE}.bak.${TS}"
  printf '%s\n' "$DESIRED" > "$OUT_FILE"
  CHANGED=1
fi

echo
if (( CLEAN_COUNT > 0 )); then
  echo "(≖‿‿≖) hehe, I fixed $KEY_COUNT key(s) across $CLEAN_COUNT file(s)."
else
  echo "(•‿‿•) yay! no messy stray bt-tether keys found."
fi

if (( CHANGED )); then
  echo
  echo "Restart me with:"
  echo "    sudo systemctl restart pwnagotchi"
  echo " or just run: pwnkill"
  echo
  echo -e "\e[32m(♥‿‿♥) thx trainer, my bt tether settings are super clean now!\e[0m"
else
  echo
  echo -e "\e[32m(^‿‿^) nothing to do — already perfect!\e[0m"
fi

# Check for unknown TOML files
detect_unknown_tomls "$CONF_DIR" "${SCRIPT_DIR}/templates"
