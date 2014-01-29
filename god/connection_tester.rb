TESTER      = "#{HOME}/PrintToPi/connection_tester.rb"

unless File.exists? CONFIG_FILE
  God.watch do |w|
    w.name  = "connection_tester"
    w.start = "ruby #{TESTER}"
    w.uid   = 'pi'
    w.gid   = 'pi'
    w.log   = '/var/PrintToPeer/logs/connection_tester.log'

    w.start_grace = 20.seconds
    w.keepalive(memory_max: 30.megabytes,
                cpu_max:    60.percent)
  end
end