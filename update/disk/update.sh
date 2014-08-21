#!/bin/bash

sudo rm -f /var/cache/apt/*

if ls -l /var/cache | grep "w" | grep -q " apt"; then
  echo "Fixing apt cache permissions"
  sudo mount / -o remount,rw
  sudo chmod ugo-w /ro/var/cache/apt
  sudo mount / -o remount

  sudo chmod ugo-w /var/cache/apt
else
  echo "Apt cache permissions OK"
fi
