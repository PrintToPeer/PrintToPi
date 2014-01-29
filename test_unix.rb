require 'eventmachine'
require 'msgpack'

module TestUnix
  def post_init
    @unpacker = MessagePack::Unpacker.new(symbolize_keys: true)
    # my_sequence = ['M108 S0','G28', 'M84']
    # my_sequence = ['M72 P1']
    EM::Timer.new(1){
      send_data MessagePack.pack(action: 'subscribe', data: {type: 'temperature'})
      # send_data MessagePack.pack({:action=>"send_commands", :data=>["G28"]})
      # send_data MessagePack.pack(action: 'send_commands', data: my_sequence)
      # send_data MessagePack.pack(action: 'print_file', data: '/home/kazw/butterfly.gcode')
    }
    EM::Timer.new(5){
      # send_data MessagePack.pack(action: 'subscribe', data: {type: 'all'})
      # send_data MessagePack.pack({:action=>"send_commands", :data=>["G28"]})
      # send_data MessagePack.pack(action: 'send_commands', data: my_sequence)
      # send_data MessagePack.pack(action: 'print_file', data: '/home/kazw/butterfly.gcode')
    }
  end

  def receive_data(data)
    @unpacker.feed_each(data) {|object| got_object(object) }
  end

  def got_object(object)
    p object
  end

  def unbind
    EM.stop
  end
end

EM.run {
  Signal.trap("INT")  { EM.stop }
  Signal.trap("TERM") { EM.stop }

  EventMachine.connect_unix_domain("/tmp/PrintToPeer/socks/ttyACM0.sock", TestUnix)
}
