#!/usr/bin/env python

# This file is part of the Printrun suite.
#
# Printrun is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Printrun is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Printrun.  If not, see <http://www.gnu.org/licenses/>.

__version__ = "2013.10.19"

from serial import Serial, SerialException
from select import error as SelectError
from threading import Thread, Lock
from Queue import Queue, Empty as QueueEmpty
import time
import sys
import platform
import os
import traceback
import errno
import socket
import re
from functools import wraps
from collections import deque
from printrun.GCodeAnalyzer import GCodeAnalyzer
from printrun.printrun_utils import install_locale, decode_utf8
install_locale('pronterface')

def locked(f):
    @wraps(f)
    def inner(*args, **kw):
        with inner.lock:
            return f(*args, **kw)
    inner.lock = Lock()
    return inner

def control_ttyhup(port, disable_hup):
    """Controls the HUPCL"""
    if platform.system() == "Linux":
        if disable_hup:
            os.system("stty -F %s -hup" % port)
        else:
            os.system("stty -F %s hup" % port)

def enable_hup(port):
    control_ttyhup(port, False)

def disable_hup(port):
    control_ttyhup(port, True)

class printcore():
    def __init__(self, port = None, baud = None):
        """Initializes a printcore instance. Pass the port and baud rate to
           connect immediately"""
        self.baud = None
        self.port = None
        self.analyzer = GCodeAnalyzer()
        self.printer = None  # Serial instance connected to the printer,
                             # should be None when disconnected
        self.clear = 0  # clear to send, enabled after responses
        self.online = False  # The printer has responded to the initial command
                             # and is active
        self.printing = False  # is a print currently running, true if printing
                               # , false if paused
        self.mainqueue = None
        self.priqueue = Queue(0)
        self.queueindex = 0
        self.lineno = 0
        self.resendfrom = -1
        self.paused = False
        self.sentlines = {}
        self.log = deque(maxlen = 10000)
        self.sent = []
        self.writefailures = 0
        self.tempcb = None  # impl (wholeline)
        self.recvcb = None  # impl (wholeline)
        self.sendcb = None  # impl (wholeline)
        self.preprintsendcb = None  # impl (wholeline)
        self.printsendcb = None  # impl (wholeline)
        self.layerchangecb = None  # impl (wholeline)
        self.errorcb = None  # impl (wholeline)
        self.startcb = None  # impl ()
        self.endcb = None  # impl ()
        self.onlinecb = None  # impl ()
        self.loud = False  # emit sent and received lines to terminal
        self.greetings = ['start', 'Grbl ']
        self.wait = 0  # default wait period for send(), send_now()
        self.read_thread = None
        self.stop_read_thread = False
        self.send_thread = None
        self.stop_send_thread = False
        self.print_thread = None
        if port is not None and baud is not None:
            self.connect(port, baud)
        self.xy_feedrate = None
        self.z_feedrate = None
        self.pronterface = None

    @locked
    def disconnect(self):
        """Disconnects from printer and pauses the print
        """
        if self.printer:
            if self.read_thread:
                self.stop_read_thread = True
                self.read_thread.join()
                self.read_thread = None
            if self.print_thread:
                self.printing = False
                self.print_thread.join()
            self._stop_sender()
            try:
                self.printer.close()
            except socket.error:
                pass
            except OSError:
                pass
        self.printer = None
        self.online = False
        self.printing = False

    @locked
    def connect(self, port = None, baud = None):
        """Set port and baudrate if given, then connect to printer
        """
        if self.printer:
            self.disconnect()
        if port is not None:
            self.port = port
        if baud is not None:
            self.baud = baud
        if self.port is not None and self.baud is not None:
            # Connect to socket if "port" is an IP, device if not
            host_regexp = re.compile("^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$|^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$")
            is_serial = True
            if ":" in port:
                bits = port.split(":")
                if len(bits) == 2:
                    hostname = bits[0]
                    try:
                        port = int(bits[1])
                        if host_regexp.match(hostname) and 1 <= port <= 65535:
                            is_serial = False
                    except:
                        pass
            self.writefailures = 0
            if not is_serial:
                self.printer_tcp = socket.socket(socket.AF_INET,
                                                 socket.SOCK_STREAM)
                self.timeout = 0.25
                self.printer_tcp.settimeout(1.0)
                try:
                    self.printer_tcp.connect((hostname, port))
                    self.printer_tcp.settimeout(self.timeout)
                    self.printer = self.printer_tcp.makefile()
                except socket.error as e:
                    print _("Could not connect to %s:%s:") % (hostname, port)
                    self.printer = None
                    self.printer_tcp = None
                    print _("Socket error %s:") % e.errno,
                    print e.strerror
                    return
            else:
                disable_hup(self.port)
                self.printer_tcp = None
                try:
                    self.printer = Serial(port = self.port,
                                          baudrate = self.baud,
                                          timeout = 0.25)
                except SerialException as e:
                    print _("Could not connect to %s at baudrate %s:") % (self.port, self.baud)
                    self.printer = None
                    print _("Serial error: %s") % e
                    return
            self.stop_read_thread = False
            self.read_thread = Thread(target = self._listen)
            self.read_thread.start()
            self._start_sender()

    def reset(self):
        """Reset the printer
        """
        if self.printer and not self.printer_tcp:
            self.printer.setDTR(1)
            time.sleep(0.2)
            self.printer.setDTR(0)

    def _readline(self):
        try:
            try:
                line = self.printer.readline()
                if self.printer_tcp and not line:
                    raise OSError(-1, "Read EOF from socket")
            except socket.timeout:
                return ""

            if len(line) > 1:
                self.log.append(line)
                if self.recvcb:
                    try: self.recvcb(line)
                    except: pass
                if self.loud: print "RECV:", line.rstrip()
            return line
        except SelectError as e:
            if 'Bad file descriptor' in e.args[1]:
                print _(u"Can't read from printer (disconnected?) (SelectError {0}): {1}").format(e.errno, decode_utf8(e.strerror))
                return None
            else:
                print _(u"SelectError ({0}): {1}").format(e.errno, decode_utf8(e.strerror))
                raise
        except SerialException as e:
            print _(u"Can't read from printer (disconnected?) (SerialException): {0}").format(decode_utf8(str(e)))
            return None
        except socket.error as e:
            print _(u"Can't read from printer (disconnected?) (Socket error {0}): {1}").format(e.errno, decode_utf8(e.strerror))
            return None
        except OSError as e:
            if e.errno == errno.EAGAIN:  # Not a real error, no data was available
                return ""
            print _(u"Can't read from printer (disconnected?) (OS Error {0}): {1}").format(e.errno, e.strerror)
            return None

    def _listen_can_continue(self):
        if self.printer_tcp:
            return not self.stop_read_thread and self.printer
        return (not self.stop_read_thread
                and self.printer
                and self.printer.isOpen())

    def _listen_until_online(self):
        while not self.online and self._listen_can_continue():
            self._send("M105")
            if self.writefailures >= 4:
                print _("Aborting connection attempt after 4 failed writes.")
                return
            empty_lines = 0
            while self._listen_can_continue():
                line = self._readline()
                if line is None: break  # connection problem
                # workaround cases where M105 was sent before printer Serial
                # was online an empty line means read timeout was reached,
                # meaning no data was received thus we count those empty lines,
                # and once we have seen 15 in a row, we just break and send a
                # new M105
                # 15 was chosen based on the fact that it gives enough time for
                # Gen7 bootloader to time out, and that the non received M105
                # issues should be quite rare so we can wait for a long time
                # before resending
                if not line:
                    empty_lines += 1
                    if empty_lines == 15: break
                else: empty_lines = 0
                if line.startswith(tuple(self.greetings)) \
                   or line.startswith('ok') or "T:" in line:
                    if self.onlinecb:
                        try: self.onlinecb()
                        except: pass
                    self.online = True
                    return

    def _listen(self):
        """This function acts on messages from the firmware
        """
        self.clear = True
        if not self.printing:
            self._listen_until_online()
        while self._listen_can_continue():
            line = self._readline()
            if line is None:
                break
            if line.startswith('DEBUG_'):
                continue
            if line.startswith(tuple(self.greetings)) or line.startswith('ok'):
                self.clear = True
            if line.startswith('ok') and "T:" in line and self.tempcb:
                #callback for temp, status, whatever
                try: self.tempcb(line)
                except: pass
            elif line.startswith('Error'):
                if self.errorcb:
                    #callback for errors
                    try: self.errorcb(line)
                    except: pass
            # Teststrings for resend parsing       # Firmware     exp. result
            # line="rs N2 Expected checksum 67"    # Teacup       2
            if line.lower().startswith("resend") or line.startswith("rs"):
                for haystack in ["N:", "N", ":"]:
                    line = line.replace(haystack, " ")
                linewords = line.split()
                while len(linewords) != 0:
                    try:
                        toresend = int(linewords.pop(0))
                        self.resendfrom = toresend
                        #print str(toresend)
                        break
                    except:
                        pass
                self.clear = True
        self.clear = True

    def _start_sender(self):
        self.stop_send_thread = False
        self.send_thread = Thread(target = self._sender)
        self.send_thread.start()

    def _stop_sender(self):
        if self.send_thread:
            self.stop_send_thread = True
            self.send_thread.join()
            self.send_thread = None

    def _sender(self):
        while not self.stop_send_thread:
            try:
                command = self.priqueue.get(True, 0.1)
            except QueueEmpty:
                continue
            while self.printer and self.printing and not self.clear:
                time.sleep(0.001)
            self._send(command)
            while self.printer and self.printing and not self.clear:
                time.sleep(0.001)

    def _checksum(self, command):
        return reduce(lambda x, y: x ^ y, map(ord, command))

    def startprint(self, gcode, startindex = 0):
        """Start a print, gcode is an array of gcode commands.
        returns True on success, False if already printing.
        The print queue will be replaced with the contents of the data array,
        the next line will be set to 0 and the firmware notified. Printing
        will then start in a parallel thread.
        """
        if self.printing or not self.online or not self.printer:
            return False
        self.printing = True
        self.mainqueue = gcode
        self.lineno = 0
        self.queueindex = startindex
        self.resendfrom = -1
        self.clear = False
        self._send("M110", -1, True)
        if not gcode.lines:
            return True
        resuming = (startindex != 0)
        self.print_thread = Thread(target = self._print,
                                   kwargs = {"resuming": resuming})
        self.print_thread.start()
        return True

    # run a simple script if it exists, no multithreading
    def runSmallScript(self, filename):
        if filename is None: return
        f = None
        try:
            with open(filename) as f:
                for i in f:
                    l = i.replace("\n", "")
                    l = l[:l.find(";")]  # remove comments
                    self.send_now(l)
        except:
            pass

    def pause(self):
        """Pauses the print, saving the current position.
        """
        if not self.printing: return False
        self.paused = True
        self.printing = False

        # try joining the print thread: enclose it in try/except because we
        # might be calling it from the thread itself
        try:
            self.print_thread.join()
        except:
            pass

        self.print_thread = None

        # saves the status
        self.pauseX = self.analyzer.x - self.analyzer.xOffset
        self.pauseY = self.analyzer.y - self.analyzer.yOffset
        self.pauseZ = self.analyzer.z - self.analyzer.zOffset
        self.pauseE = self.analyzer.e - self.analyzer.eOffset
        self.pauseF = self.analyzer.f
        self.pauseRelative = self.analyzer.relative

    def resume(self):
        """Resumes a paused print.
        """
        if not self.paused: return False
        if self.paused:
            # restores the status
            self.send_now("G90")  # go to absolute coordinates

            xyFeedString = ""
            zFeedString = ""
            if self.xy_feedrate is not None:
                xyFeedString = " F" + str(self.xy_feedrate)
            if self.z_feedrate is not None:
                zFeedString = " F" + str(self.z_feedrate)

            self.send_now("G1 X%s Y%s%s" % (self.pauseX, self.pauseY,
                                            xyFeedString))
            self.send_now("G1 Z" + str(self.pauseZ) + zFeedString)
            self.send_now("G92 E" + str(self.pauseE))

            # go back to relative if needed
            if self.pauseRelative: self.send_now("G91")
            # reset old feed rate
            self.send_now("G1 F" + str(self.pauseF))

        self.paused = False
        self.printing = True
        self.print_thread = Thread(target = self._print,
                                   kwargs = {"resuming": True})
        self.print_thread.start()

    def send(self, command, wait = 0):
        """Adds a command to the checksummed main command queue if printing, or
        sends the command immediately if not printing"""

        if self.online:
            if self.printing:
                self.mainqueue.append(command)
            else:
                self.priqueue.put_nowait(command)
        else:
            print "Not connected to printer."

    def send_now(self, command, wait = 0):
        """Sends a command to the printer ahead of the command queue, without a
        checksum"""
        if self.online:
            self.priqueue.put_nowait(command)
        else:
            print "Not connected to printer."

    def _print(self, resuming = False):
        self._stop_sender()
        try:
            if self.startcb:
                #callback for printing started
                try: self.startcb(resuming)
                except:
                    print "Print start callback failed with:"
                    traceback.print_exc(file = sys.stdout)
            while self.printing and self.printer and self.online:
                self._sendnext()
            self.sentlines = {}
            self.log.clear()
            self.sent = []
            if self.endcb:
                #callback for printing done
                try: self.endcb()
                except:
                    print "Print end callback failed with:"
                    traceback.print_exc(file = sys.stdout)
        except:
            print "Print thread died due to the following error:"
            traceback.print_exc(file = sys.stdout)
        finally:
            self.print_thread = None
            self._start_sender()

    #now only "pause" is implemented as host command
    def processHostCommand(self, command):
        command = command.lstrip()
        if command.startswith(";@pause"):
            if self.pronterface is not None:
                self.pronterface.pause(None)
            else:
                self.pause()

    def _sendnext(self):
        if not self.printer:
            return
        while self.printer and self.printing and not self.clear:
            time.sleep(0.001)
        self.clear = False
        if not (self.printing and self.printer and self.online):
            self.clear = True
            return
        if self.resendfrom < self.lineno and self.resendfrom > -1:
            self._send(self.sentlines[self.resendfrom], self.resendfrom, False)
            self.resendfrom += 1
            return
        self.resendfrom = -1
        if not self.priqueue.empty():
            self._send(self.priqueue.get_nowait())
            self.priqueue.task_done()
            return
        if self.printing and self.queueindex < len(self.mainqueue):
            (layer, line) = self.mainqueue.idxs(self.queueindex)
            gline = self.mainqueue.all_layers[layer][line]
            if self.layerchangecb and self.queueindex > 0:
                (prev_layer, prev_line) = self.mainqueue.idxs(self.queueindex - 1)
                if prev_layer != layer:
                    try: self.layerchangecb(layer)
                    except: traceback.print_exc()
            if self.preprintsendcb:
                if self.queueindex + 1 < len(self.mainqueue):
                    (next_layer, next_line) = self.mainqueue.idxs(self.queueindex + 1)
                    next_gline = self.mainqueue.all_layers[next_layer][next_line]
                else:
                    next_gline = None
                gline = self.preprintsendcb(gline, next_gline)
            if gline is None:
                self.queueindex += 1
                self.clear = True
                return
            tline = gline.raw
            if tline.lstrip().startswith(";@"):  # check for host command
                self.processHostCommand(tline)
                self.queueindex += 1
                self.clear = True
                return

            tline = tline.split(";")[0]
            if len(tline) > 0:
                self._send(tline, self.lineno, True)
                self.lineno += 1
                if self.printsendcb:
                    try: self.printsendcb(gline)
                    except: traceback.print_exc()
            else:
                self.clear = True
            self.queueindex += 1
        else:
            self.printing = False
            self.clear = True
            if not self.paused:
                self.queueindex = 0
                self.lineno = 0
                self._send("M110", -1, True)

    def _send(self, command, lineno = 0, calcchecksum = False):
        if calcchecksum:
            prefix = "N" + str(lineno) + " " + command
            command = prefix + "*" + str(self._checksum(prefix))
            if "M110" not in command:
                self.sentlines[lineno] = command
        if self.printer:
            self.sent.append(command)
            # run the command through the analyzer
            try: self.analyzer.Analyze(command)
            except:
                print "Warning: could not analyze command %s:" % command
                traceback.print_exc(file = sys.stdout)
            if self.loud:
                print "SENT:", command
            if self.sendcb:
                try: self.sendcb(command)
                except: pass
            try:
                self.printer.write(str(command + "\n"))
                if self.printer_tcp: self.printer.flush()
                self.writefailures = 0
            except socket.error as e:
                print _(u"Can't write to printer (disconnected?) (Socket error {0}): {1}").format(e.errno, decode_utf8(e.strerror))
                self.writefailures += 1
            except SerialException as e:
                print _(u"Can't write to printer (disconnected?) (SerialException): {0}").format(decode_utf8(str(e)))
                self.writefailures += 1
            except RuntimeError as e:
                print _(u"Socket connection broken, disconnected. ({0}): {1}").format(e.errno, decode_utf8(e.strerror))
                self.writefailures += 1
