#!/bin/bash

sudo mount / -o remount,rw
/home/pi/PrintToPi/update/pyserial/update.py
sudo mount / -o remount
