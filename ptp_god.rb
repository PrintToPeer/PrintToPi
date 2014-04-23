require 'fileutils'

HOME        = '/home/pi'
CONFIG_FILE = "#{HOME}/ptp-config.yml"
PID_DIR     = '/tmp/PrintToPeer/pids'

FileUtils.mkdir_p PID_DIR
FileUtils.chown_R('pi', 'dialout', '/tmp/PrintToPeer')
FileUtils.chmod_R(0770, '/tmp/PrintToPeer')

God.pid_file_directory = PID_DIR
God.load '/etc/ptp_god/*.rb'
