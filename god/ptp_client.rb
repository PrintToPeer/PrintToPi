SERVER      = "#{HOME}/PrintToPi/ptp_client.rb"

God.watch do |w|
  w.name  = "status_server"
  w.start = "ruby #{SERVER}"
  w.uid  = 'pi'
  w.gid  = 'pi'
  w.log  = '/var/PrintToPeer/logs/ptp_client.log'

  w.start_grace = 30.seconds
  if File.exists? CONFIG_FILE
    w.keepalive(memory_max: 30.megabytes,
                cpu_max:    30.percent)
  else
    w.keepalive
  end
end

