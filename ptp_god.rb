require 'fileutils'

HOME        = '/home/pi'
CONFIG_FILE = "#{HOME}/ptp-config.yml"
PID_DIR     = "/tmp/PrintToPeer_God/pids"

FileUtils.mkdir_p PID_DIR
FileUtils.chmod 770, "/tmp/PrintToPeer_God"
FileUtils.chmod 770, PID_DIR

God.pid_file_directory = PID_DIR
God.load '/etc/ptp_god/*.rb'
