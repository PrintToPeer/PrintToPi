#!/usr/bin/env python

import sys
import serial
import subprocess

print "Checking pyserial-2.7..."

if serial.VERSION != '2.7':
  subprocess.Popen('/home/pi/PrintToPi/update/pyserial/update.sh')

