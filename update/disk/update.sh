#!/bin/bash

if ls -l /var/cache | grep -q " apt"; then
  echo "Fixing apt cache permissions"
  sudo mount / -o remount,rw
  sudo rm -rf /ro/var/cache/apt
  sudo rm -rf /var/cache/apt
  sudo mount / -o remount
else
  echo "Apt cache permissions OK"
fi
