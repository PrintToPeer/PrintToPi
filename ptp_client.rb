if File.exists? '/boot/host.rb'
  load '/boot/host.rb'
else
  HTTP_HOST = "https://printtopeer.io"
  SOCKET_HOST = "wss://printtopeer.io"
end

require 'eventmachine'
require 'faye/websocket'
require 'yajl/json_gem'
require 'msgpack'
require 'yaml'
require 'em-http'
require 'fileutils'

Dir["/home/pi/PrintToPi/ptp-client/*.rb"].each { |f| require f }

p `/home/pi/PrintToPi/update/update_all.sh`

EM.run {
  Signal.trap('INT')  { EM.stop }
  Signal.trap('TERM') { EM.stop }

  client = PrintToClient.new(host: SOCKET_HOST)
  EM.stop unless client.configured?
}
