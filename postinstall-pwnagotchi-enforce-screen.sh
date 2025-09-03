#!/usr/bin/env bash
# Pwnagotchi-style display config enforcer (idempotent, change-aware)

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Template filenames (defined early for help text)
TEMPLATE_BASE_NAME="10-display.toml"
TEMPLATE_OVERRIDE_NAME="99-display.override.toml"

# --- help check FIRST (before root check) ---
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage:
  sudo ./$(basename "$0") \
    [--force] \
    [--type "<display_type>"] \
    [--rotation <0|90|180|270>] \
    [--invert <true|false>]

How it decides what to write:
  1) If templates/${TEMPLATE_OVERRIDE_NAME} exists, it is used as-is (preferred).
  2) Otherwise, templates/${TEMPLATE_BASE_NAME} is loaded and the values for
     display type, rotation, and invert are filled from CLI arguments.
     All three fields are REQUIRED; the script fails if any end up empty.

What it does:
  - Comments out stray ui.display.* / ui.invert keys in conf.d/*
  - Ensures conf.d/${TEMPLATE_BASE_NAME} has your chosen values
  - Prints restart hint only if something changed

Environment:
  - Automatically detects Pwnagotchi devices (Raspberry Pi + pwnagotchi indicators)
  - Use --force to bypass detection and run on any system

Tips:
  - Create templates/${TEMPLATE_OVERRIDE_NAME} once with your real values and
    skip CLI flags forever (keep it .gitignored).

Example:
  sudo ./$(basename "$0") \
    --type "waveshare_4" --rotation 180 --invert true
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

# Templates (base is required; override is optional and ignored by git)
TEMPLATE_BASE="${SCRIPT_DIR}/templates/${TEMPLATE_BASE_NAME}"
TEMPLATE_OVERRIDE="${SCRIPT_DIR}/templates/${TEMPLATE_OVERRIDE_NAME}"

DISPLAY_TYPE=""
DISPLAY_ROTATION=""
DISPLAY_INVERT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)     DISPLAY_TYPE="${2:-}";     shift 2 ;;
    --rotation) DISPLAY_ROTATION="${2:-}"; shift 2 ;;
    --invert)   DISPLAY_INVERT="${2:-}";   shift 2 ;;
    *) echo "(•_•?) unknown arg: $1" >&2; exit 2 ;;
  esac
done

CONF_DIR="/etc/pwnagotchi/conf.d"
OUT_FILE="${CONF_DIR}/${TEMPLATE_BASE_NAME}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CONF_DIR"

# --- helpers ---
escape_sed() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
get_toml_val() {
  local key="$1" file="$2"
  # extract value, handling both quoted and unquoted values, ignoring comments
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" \
    | sed -E 's/^[^=]*=\s*"([^"]*)".*/\1/; t; s/^[^=]*=\s*([^#[:space:]]+).*/\1/' \
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
    "ui\\.display\\.type|$DISPLAY_TYPE" \
    "ui\\.display\\.rotation|$DISPLAY_ROTATION" \
    "ui\\.invert|$DISPLAY_INVERT"
  do
    key="${pair%%|*}"; val="${pair#*|}"
    if [[ -z "$val" ]]; then
      echo "(☉_☉ ) missing required flag for ${key##*.} (see --help)"; exit 3
    fi
    # Handle boolean and numeric values (no quotes for rotation and boolean)
    if [[ "$key" == "ui.display.rotation" ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]]; then
      tmp="$(sed -E \
        "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*).*|\\1$(escape_sed "$val")|g" \
        <<< "$tmp")"
    else
      tmp="$(sed -E \
        "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\\1\"$(escape_sed "$val")\"|g" \
        <<< "$tmp")"
    fi
  done

  DESIRED="$tmp"
  SOURCE="template+cli"
fi

# --- validate resulting config (no empties, correct formats) ---
tmpfile="$(mktemp)"; trap 'rm -f "$tmpfile"' EXIT
printf '%s\n' "$DESIRED" > "$tmpfile"

VAL_TYPE="$(get_toml_val 'ui\.display\.type' "$tmpfile")"
VAL_ROTATION="$(get_toml_val 'ui\.display\.rotation' "$tmpfile")"
VAL_INVERT="$(get_toml_val 'ui\.invert' "$tmpfile")"

if [[ -z "$VAL_TYPE" || -z "$VAL_ROTATION" || -z "$VAL_INVERT" ]]; then
  echo "(╥☁╥ ) the resulting config has empty fields. Fix your ${SOURCE} input." >&2
  exit 4
fi

# Validate rotation
case "$VAL_ROTATION" in
  0|90|180|270) ;;
  *) echo "(≖__≖) rotation must be 0, 90, 180, or 270 (got: $VAL_ROTATION)"; exit 5 ;;
esac

# Validate invert
case "$VAL_INVERT" in
  true|false) ;;
  *) echo "(≖__≖) invert must be 'true' or 'false' (got: $VAL_INVERT)"; exit 6 ;;
esac

echo "(◕‿◕) using source: ${SOURCE}"

# Keys we manage
KEY_RE='(ui\.display\.(enabled|type|rotation)|ui\.invert)'


# --- de-stray managed keys from other TOMLs ---
echo "(◕‿◕) scanning $CONF_DIR for messy display configs …"

CLEAN_COUNT=0
KEY_COUNT=0
CHANGED=0

# 1) Tidy other conf files
for f in "$CONF_DIR"/*.toml; do
  [[ -f "$f" ]] || continue
  [[ "$f" == "$OUT_FILE" ]] && continue
  if grep -Eq "^[[:space:]]*${KEY_RE}[[:space:]]*=" "$f"; then
    MOVED=$(grep -Ec "^[[:space:]]*${KEY_RE}[[:space:]]*=" "$f" || true)
    echo "(☉_☉ ) trainer, $(basename "$f") has $MOVED stray display key(s)!"
    echo "        → backup: ${f}.bak.${TS}"
    cp -a "$f" "${f}.bak.${TS}"
    # Comment out strays
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
  echo "(✜‿‿✜) writing my perfect display config to $(basename "$OUT_FILE") …"
  [[ -f "$OUT_FILE" ]] && cp -a "$OUT_FILE" "${OUT_FILE}.bak.${TS}"
  printf '%s\n' "$DESIRED" > "$OUT_FILE"
  CHANGED=1
fi

echo
if (( CLEAN_COUNT > 0 )); then
  echo "(≖‿‿≖) hehe, I fixed $KEY_COUNT key(s) across $CLEAN_COUNT file(s)."
else
  echo "(•‿‿•) yay! no messy stray display keys found."
fi

if (( CHANGED )); then
  echo
  echo "Restart me with:"
  echo "    sudo systemctl restart pwnagotchi"
  echo " or just run: pwnkill"
  echo
  echo -e "\e[32m(♥‿‿♥) thx trainer, my display settings are super clean now!\e[0m"
else
  echo
  echo -e "\e[32m(^‿‿^) nothing to do — already perfect!\e[0m"
fi

# Check for unknown TOML files
detect_unknown_tomls "$CONF_DIR" "${SCRIPT_DIR}/templates"
