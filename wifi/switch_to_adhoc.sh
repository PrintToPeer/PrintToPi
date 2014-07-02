#!/bin/bash

sudo cp adhoc.conf /etc/wpa_supplicant/wpa_supplicant.conf
sudo wpa_cli reconfigure

sleep 4
sudo ip addr add 169.254.1.1/16 dev wlan0
