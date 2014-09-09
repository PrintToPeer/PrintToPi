#!/bin/bash

LOCAL_TAG='pi-version-14'

cd /home/pi/Burijji
BURIJJI_TAG=`git describe --abbrev=0 --tags`

echo "Checking Burijji Version: PrintToPi is '$LOCAL_TAG', Burijji is '$BURIJJI_TAG'"

if [ "$BURIJJI_TAG" != "$LOCAL_TAG" ]; then
  cd /ro/home/pi/Burijji

  sudo mount / -o remount,rw
  git pull origin master
  git pull origin master --tags
  git checkout tags/$LOCAL_TAG
  sudo mount / -o remount
fi
