#!/usr/bin/env bash
# environment-detection.sh
# Shared environment detection functions for pwnagotchi-postinstall scripts

# Detect if we're on a Raspberry Pi
is_raspberry_pi() {
  grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null
}

# Detect if we're on a Pwnagotchi system
is_pwnagotchi() {
  [[ -d "/etc/pwnagotchi" ]] || \
  hostname | grep -qi 'pwnagotchi' || \
  [[ -f "/usr/local/bin/pwnagotchi" ]]
}

# Ensure we're NOT on a Pwnagotchi (for SD card modification scripts)
ensure_not_on_pwnagotchi() {
  local script_name="${1:-$(basename "$0")}"
  local force_flag="${2:-false}"
  
  if [[ "$force_flag" == true ]]; then
    return 0
  fi
  
  if is_raspberry_pi || is_pwnagotchi; then
    cat >&2 <<EOF
$(echo -e "\e[31mWhoa trainer! You're on the gotchi itself — that's not how this works!\e[0m")
$(echo -e "\e[31mThis script is meant to be run *on your computer*, right after flashing the SD card.\e[0m")
$(echo -e "\e[31m   Why? Because on your PC, the FAT32 boot partition is safely writable.\e[0m")
$(echo -e "\e[31m   But on the running Pi, /boot is remapped and files like cmdline.txt are already in use.\e[0m")
$(echo -e "\e[31m   Editing them live might do *nothing* — or soft-brick your gotchi mid-run. Not cool.\e[0m")
$(echo -e "\e[31mSo go mount that SD card on your computer and run me there!\e[0m")
$(echo -e "\e[31m(╯°□°）╯︵ ┻━┻\e[0m")
EOF
    exit 1
  fi
}

# Ensure we're ON a Pwnagotchi (for configuration scripts)
ensure_on_pwnagotchi() {
  local script_name="${1:-$(basename "$0")}"
  local force_flag="${2:-false}"
  
  if [[ "$force_flag" == true ]]; then
    return 0
  fi
  
  if ! is_raspberry_pi && ! is_pwnagotchi; then
    cat >&2 <<EOF
$(echo -e "\e[31mಠ_ಠ Hold up trainer! This doesn't look like a Pwnagotchi device.\e[0m")
$(echo -e "\e[31m     I'm designed to configure /etc/pwnagotchi/ on actual Pwnagotchi hardware.\e[0m")
$(echo -e "\e[31m     Running me elsewhere might create confusing config files.\e[0m")
$(echo -e "\e[31mIf you really know what you're doing, use:\e[0m")
$(echo -e "\e[31m     sudo $script_name --force [other args]\e[0m")
$(echo -e "\e[31m(╯°□°）╯︵ ┻━┻\e[0m")
EOF
    exit 1
  fi
}