#!/bin/bash

echo Updating pyserial-2.7...

sudo mount / -o remount,rw
cd /home/pi/PrintToPi/update/pyserial
rm -r pyserial-2.7/
tar xzvf pyserial-2.7.tar.gz
cd pyserial-2.7
python setup.py build
sudo python setup.py install
sudo mount / -o remount

cd -

echo " => Done"
