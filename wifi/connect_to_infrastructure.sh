#!/bin/bash

sudo killall connect_to_adhoc.sh
sudo killall adhoc_daemon.sh
sudo killall dhcpd
sleep 2

sudo killall -9 connect_to_adhoc.sh
sudo killall -9 adhoc_daemon.sh
sudo killall -9 dhcpd
sudo ifdown --force wlan0

sudo cp ~/PrintToPi/wifi/infrastructure.interfaces /etc/network/interfaces
sudo cp ~/PrintToPi/wifi/active-infrastructure.conf /etc/wpa_supplicant/wpa_supplicant.conf
sudo ifup wlan0
