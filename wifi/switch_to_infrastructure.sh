#!/bin/bash

sudo killall dhcpd

sudo cp infrastructure.conf /etc/wpa_supplicant/wpa_supplicant.conf
sudo wpa_cli reconfigure

