#!/bin/bash

if [ -e /home/pi/Burijji ]; then
  echo "Uninstalling System Burijji..."
  sudo mount / -o remount,rw
  sudo rm -rf /home/pi/Burijji
  sudo rm -rf /ro/home/pi/Burijji
  sudo mount / -o remount
fi
