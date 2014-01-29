HOME        = '/home/pi'
CONFIG_FILE = "#{HOME}/ptp-config.yml"

God.pid_file_directory = '/var/PrintToPeer/pids'
God.load '/etc/ptp_god/*.rb'