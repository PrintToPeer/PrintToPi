#!/bin/bash

if [ "`md5sum /home/pi/Burijji/Printrun/printrun/printcore.py`" != "54a7a7807e1c7f541f3b79d2afaa65d4  /home/pi/Burijji/Printrun/printrun/printcore.py" ]; then
  echo "Patching printcore.py"
  sudo mount / -o remount,rw
  cp /home/pi/PrintToPi/update/printcore/printcore-patched.py /ro/home/pi/Burijji/Printrun/printrun/printcore.py
  cp /home/pi/PrintToPi/update/printcore/printcore-patched.py /home/pi/Burijji/Printrun/printrun/printcore.py
  sudo mount / -o remount
fi
