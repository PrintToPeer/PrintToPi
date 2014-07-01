#!/bin/bash

sudo cp none.conf /etc/wpa_supplicant/wpa_supplicant.conf
sudo wpa_cli reconfigure

sudo reboot
