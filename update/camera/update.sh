#!/bin/bash

if grep -q "start_x=1" /boot/config.txt; then
  echo Camera OK
else
  echo Installing camera support...

  sudo mount /boot -o remount,rw
  sudo bash -c 'sed /boot/config.txt -i -e "s/^startx/#startx/"'
  sudo bash -c 'sed /boot/config.txt -i -e "s/^start_x/#start_x/"'
  sudo bash -c 'sed /boot/config.txt -i -e "s/^gpu_mem=.*$/gpu_mem=64/"'
  sudo bash -c 'echo "start_x=1" >> /boot/config.txt'
  sudo mount /boot -o remount

  echo Done. Rebooting Now.

  sudo reboot
  sleep 30
fi
