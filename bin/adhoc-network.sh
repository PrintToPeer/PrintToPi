#!/bin/bash

sudo killall wpa_supplicant
sudo iwconfig wlan0 mode ad-hoc
sleep 2

sudo iwconfig wlan0 essid "New PrintToPi" mode ad-hoc
sleep 2

sudo ip addr add 10.0.213.1/16 dev wlan0
sleep 2

sudo killall dhcpd
sudo dhcpd
sleep 2
