load '/boot/host.rb'
require 'faye/websocket'
require 'eventmachine'
require 'yajl/json_gem'
require 'yaml'

$config_file = "#{ENV['HOME']}/ptp-config.yml"
$test_file   = "#{ENV['HOME']}/ptp-connection-test"
$url         = SOCKET_HOST

def make_response(id: rand(1..100000), action: nil, data: {})
  [action, id: id, channel: nil, data: data, token: nil].to_json
end

def run_connection_test?
  configured = File.size?($config_file) ? true : false
  do_test    = File.exists?($test_file)
  configured && do_test
end

def run_connection_test!
  return unless run_connection_test?
  File.delete($test_file)
  config    = YAML.load_file($config_file)
  ws        = Faye::WebSocket::Client.new($url)
  ws.onopen = lambda{|event| ws.send make_response(action: 'server.authenticate', data: config) }
end

EM.run{
  Signal.trap("INT")  { EM.stop }
  Signal.trap("TERM") { EM.stop }
  EM::PeriodicTimer.new(5){ run_connection_test! }
}
