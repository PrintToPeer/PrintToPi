#!/bin/bash

# HACK: Some WiFi dongles randomly dissasociate from ad-hoc networks
# This script "fixes" that problem

echo 'adhoc_daemon.sh: Started'

while true; do

  sleep 2

  if ! (/sbin/ifconfig wlan0 | grep -q 10.0.213.1) ; then
    echo 'adhoc_daemon.sh: Missing IP Address'
    ~/PrintToPi/wifi/connect_to_adhoc.sh
    break
  fi

  if ! (/sbin/iwconfig wlan0 | grep -q "New PrintToPi") ; then
    echo 'adhoc_daemon.sh: WiFi Not Associated'
    ~/PrintToPi/wifi/connect_to_adhoc.sh
    break
  fi

  if ! (pgrep "dhcpd" > /dev/null) ; then
    echo 'adhoc_daemon.sh: dhcpd not running'
    ~/PrintToPi/wifi/connect_to_adhoc.sh
    break
  fi

done
