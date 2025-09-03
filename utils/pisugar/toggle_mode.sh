#!/bin/bash

if [ -f /root/.pwnagotchi-manu ]; then
  echo "Currently in MANUAL mode, switching to AUTO..."
  sudo rm -f /root/.pwnagotchi-manu
  sudo touch /root/.pwnagotchi-auto
else
  echo "Currently in AUTO mode or undefined, switching to MANUAL..."
  sudo rm -f /root/.pwnagotchi-auto
  sudo touch /root/.pwnagotchi-manu
fi

sudo systemctl restart pwnagotchi
