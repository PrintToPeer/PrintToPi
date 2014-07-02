#!/bin/bash

sudo ifdown --force wlan0

killall adhoc_daemon.sh
sudo killall dhcpd
sudo killall dhclient
sudo killall wpa_supplicant
sleep 2

sudo killall -9 dhcpd
sudo killall -9 dhclient
sudo killall -9 wpa_supplicant

sudo cp ~/PrintToPi/wifi/adhoc.interfaces /etc/network/interfaces
sleep 2

sudo ifup wlan0
sleep 2

sudo dhcpd

nohup ~/PrintToPi/wifi/adhoc_daemon.sh > /dev/null < /dev/null 2>/dev/null &
