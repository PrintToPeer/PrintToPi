#!/usr/bin/env python

import sys, os, argparse, signal, time

# Signal Handlers
server = None
def handle_signal(signal, frame):
  print "Caught signal; stopping Burijji"
  server.stop()
  sys.exit(1)

signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGHUP, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)

# Command Line Args
parser = argparse.ArgumentParser()
parser.add_argument("-p", "--port")
parser.add_argument("-s", "--socket")
parser.add_argument("-b", "--baud")
arguments = parser.parse_args()

# Configure the path
sys.path.append(os.getenv("HOME") + "/Burijji")
sys.path.append(os.getenv("HOME") + "/Burijji/mb_serial")
sys.path.append(os.getenv("HOME") + "/Burijji/Printrun")

# Build the server
import burijji
from burijji.server import BurijjiServer

server = BurijjiServer(arguments.port, arguments.socket, arguments.baud)

# Start
server.start()


# Sleep forever
while True:
  time.sleep(1)
