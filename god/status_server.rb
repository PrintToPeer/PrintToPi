SERVER      = "#{HOME}/PrintToPi/status_server.rb"

God.watch do |w|
  w.name  = "status_server"
  w.start = "ruby #{SERVER}"
  w.uid   = 'pi'
  w.gid   = 'pi'
  w.log_cmd = '/home/pi/PrintToPi/bin/log.sh /var/PrintToPeer/logs/status_server.log'

  w.start_grace = 30.seconds
  if File.exists? CONFIG_FILE
    w.keepalive(memory_max: 30.megabytes,
                cpu_max:    30.percent)
  else
    w.keepalive
  end
end