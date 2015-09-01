#!/bin/bash

echo Clearing old package...
sudo rm -rf /home/pi/printtopine

echo Updating system clock...
sudo service ntp stop
sudo ntpd -gq
sudo service ntp start

HOST=`/home/pi/PrintToPi/get_host.rb`
PACKAGE_URL="$HOST/printtopine-package.tgz"
echo Downloading package from "$PACKAGE_URL"...

cd /home/pi
curl -4L "$PACKAGE_URL" | tar xz || exit

echo Launching PrintToPine...
cd printtopine
./launch.sh
