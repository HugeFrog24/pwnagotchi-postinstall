#!/usr/bin/env bash
# Shared configuration utilities for pwnagotchi postinstall scripts

# Build known TOML files list from templates directory
# Usage: get_known_toml_files "/path/to/templates/dir"
get_known_toml_files() {
  local templates_dir="$1"
  local known_files=()
  
  # Skip if templates directory doesn't exist
  [[ -d "$templates_dir" ]] || return 1
  
  # Collect all .toml files from templates directory
  for f in "$templates_dir"/*.toml; do
    [[ -f "$f" ]] || continue
    known_files+=("$(basename "$f")")
  done
  
  # Return the array (caller should capture with readarray)
  printf '%s\n' "${known_files[@]}"
}

# Detect unknown TOML files in conf.d directory
# Usage: detect_unknown_tomls "/etc/pwnagotchi/conf.d" "/path/to/templates"
detect_unknown_tomls() {
  local conf_dir="$1"
  local templates_dir="$2"
  local unknown_files=()
  local known_files=()
  
  # Skip if directories don't exist
  [[ -d "$conf_dir" ]] || return 0
  [[ -d "$templates_dir" ]] || return 0
  
  # Get known files from templates directory
  readarray -t known_files < <(get_known_toml_files "$templates_dir")
  
  # Check each .toml file in conf.d
  for f in "$conf_dir"/*.toml; do
    [[ -f "$f" ]] || continue
    local basename
    basename="$(basename "$f")"
    local is_known=false
    
    # Check if this file is in our known list
    for known in "${known_files[@]}"; do
      if [[ "$basename" == "$known" ]]; then
        is_known=true
        break
      fi
    done
    
    # Add to unknown list if not recognized
    if [[ "$is_known" == false ]]; then
      unknown_files+=("$basename")
    fi
  done
  
  # Report findings
  if (( ${#unknown_files[@]} > 0 )); then
    echo
    echo -e "\e[33m(◉_◉) Found ${#unknown_files[@]} unmanaged TOML file(s):\e[0m"
    for f in "${unknown_files[@]}"; do
      echo -e "\e[33m        → $f\e[0m"
    done
    echo -e "\e[33m        These files are not managed by this postinstall suite\e[0m"
    echo -e "\e[33m        They aren't necessarily wrong, but consider reviewing them for overlapping config or cleanup\e[0m"
  fi
}