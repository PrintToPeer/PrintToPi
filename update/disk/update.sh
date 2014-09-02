#!/bin/bash

# The /etc/cron.daily/apt job builds a cache in /var/cache/apt
# This is problematic because /var is mounted on a ramdisk, and the 100mb+ of cache
# totally clobbers the Pi's RAM space, and causes prints to fail.

if [ -e "/etc/cron.daily/apt" ]; then
  echo "Removing apt cron job"
  sudo mount / -o remount,rw
  sudo rm /etc/cron.daily/apt
  sudo mount / -o remount
else
  echo "Apt cron OK (not present)"
fi

if [ -e "/var/cache/apt" ]; then
  echo "Removing apt cache"
  sudo mount / -o remount,rw
  sudo rm -rf /ro/var/cache/apt
  sudo rm -rf /var/cache/apt
  sudo mount / -o remount
else
  echo "Apt cache OK (not present)"
fi
