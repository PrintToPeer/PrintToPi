#!/usr/bin/env python

import sys
import subprocess

print "Checking pyserial-2.7..."

try:
  import serial
  assert(serial.VERSION == '2.7')
except:
  subprocess.Popen('/home/pi/PrintToPi/update/pyserial/update.sh')
