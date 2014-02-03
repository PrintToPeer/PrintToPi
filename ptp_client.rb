require 'eventmachine'
require 'faye/websocket'
require 'yajl/json_gem'
require 'msgpack'
require 'yaml'
require 'em-http'
require 'fileutils'

class Array
  def to_event
    event = MessagePack.unpack(self.pack('C*'), symbolize_keys: false)[0]
    {action: event[0], payload: event[1]}
  end
end

class String
  def to_event
    event = JSON.parse(self, symbolize_keys: false)[0]
    {action: event[0], payload: event[1]}
  end
end

module Helpers
  def config_file
    "#{ENV['HOME']}/ptp-config.yml"
  end

  def configured?
    File.size?(config_file) ? true : false
  end

  def load_config
    YAML.load_file(config_file) if configured?
  end

  def port_to_name(port_name)
    port_name.split('/').last
  end
end

class PtpNetwork
  attr_accessor :reconnect, :channel, :channel_token, :connected
  attr_reader   :client

  def initialize(client)
    @client        = client
    @url           = "ws://#{@client.host}/websocket"
    @reconnect     = true
    @event_handler = PtpEventHandler.new(self)
    @websocket     = Faye::WebSocket::Client.new(@url)
    setup_ws_callbacks
    setup_updates
  end

  def machine_connected(uuid)
    send(action: 'server.machine_connected', data: {uuid: uuid})
  end

  def machine_disconnected(uuid)
    send(action: 'server.machine_disconnected', data: {uuid: uuid})
  end

  def find_or_create_machine(port_info, port_name)
    send(action: 'server.find_or_create_machine', data: {port_info: port_info, port_name: port_name})
  end

  def respond_to_ping
    send(action: 'websocket_rails.pong')
  end

  def update_job_state(job_id, uuid, state)
    send(action: 'server.job_status', data: {state: state, job_id: job_id, uuid: uuid})
  end

private
  def setup_ws_callbacks
    @websocket.onopen    = lambda{|event| authenticate}
    @websocket.onmessage = lambda{|event| receive(event)}
    @websocket.onclose   = lambda{|event| reconnect}
  end

  def setup_updates
    EM::PeriodicTimer.new(1) do
      if @connected
        update_data = Hash.new
        update_data[:machines] = Hash.new
        
        @client.uuid_map.each do |uuid,port_name|
          machine = @client.machines[port_name]
          if machine.nil?
            @client.uuid_map.delete(uuid)
            machine_disconnected(uuid)
            next
          end
          machine_status = {printing: machine.printing, current_line: machine.current_line, paused: machine.paused, current_segment: machine.segment}
          update_data[:machines][uuid] = {temperatures: machine.temperatures, status: machine_status}
        end
        update_data[:uuid_map]        = @client.uuid_map
        
        @client.update_iserial_map
        update_data[:iserial_map]     = @client.iserial_map

        send(action: 'server.update_data', data: update_data) unless update_data.empty?
      end
    end
  end

  def authenticate
    @connected = true
    send(action: 'server.authenticate', data: @client.config)
  end

  def send(id: rand(1..100000), action: nil, channel: false, data: Hash.new)
    return unless @connected
    if channel
      response = [action, id: id, channel: @channel, data: data, token: @channel_token]
    else
      response = [action, id: id, channel: nil, data: data, token: nil]
    end
    @websocket.send @binary ? response.to_msgpack.bytes : response.to_json
  end

  def receive(event)
    @binary = true if event.data.is_a?(Array)
    event  = event.data.to_event
    action = event[:action].sub('.', '_') rescue event[:action].to_s.sub('.', '_')
    @event_handler.__send__(action.to_sym, event[:payload]) unless @event_handler.public_methods.grep(/\A#{action}\z/).empty?
  end

  def reconnect
    p [:no_connection, Time.now]
    @connected = false
    EM::Timer.new(15) do
      if @reconnect
        p [:reconnecting, Time.now]
        @websocket = Faye::WebSocket::Client.new(@url, nil)
        setup_ws_callbacks
      end
    end
  end
end

class PtpEventHandler
  def initialize(network)
    @network    = network
    @gcode_root = '/tmp/PrintToPeer/Gcode'
    FileUtils::mkdir_p(@gcode_root)
  end

  def client_connected(payload)
    p [:connection_opened, Time.now]
  end

  def server_authenticate(payload)
    if payload['data']['authentication']
      p [:authenticated, Time.now]
    else
      p [:authentication_failed, Time.now]
      @network.reconnect = payload['data']['do_retry']
    end
  end

  def connect_first_available(payload)
    baud   = payload['data']['baud'].to_i unless payload['data']['baud'].nil?
    @network.client.connect_first_available(baud)
  end

  def connect_machines(payload)
    @network.client.connect_machines(payload['data'])
  end

  def machine_info(payload)
    machine_uuid                           = payload['data']['uuid']
    port_name                              = payload['data']['port_name']
    @network.client.uuid_map[machine_uuid] = port_name
    p [:machine_net_connected, port_name, Time.now]

    @network.machine_connected(machine_uuid)
  end

  def send_commands(payload)
    machine_uuid = payload['data']['uuid']
    port_name    = @network.client.uuid_map[machine_uuid]
    machine      = @network.client.machines[port_name]
    p [:sending_machine_action, machine_uuid, port_name, Time.now]

    machine.send_commands(payload['data']['commands']) unless machine.nil?
  end

  def update_routines(payload)
    machine_uuid = payload['data']['uuid']
    port_name    = @network.client.uuid_map[machine_uuid]
    machine      = @network.client.machines[port_name]

    machine.update_routines(payload['data']['routines']) unless machine.nil?
  end

  def run_job(payload)
    machine_uuid = payload['data']['uuid']
    job_id       = payload['data']['job_id'].to_i
    if @network.client.uuid_map.key?(machine_uuid)
      port_name  = @network.client.uuid_map[machine_uuid]
      machine    = @network.client.machines[port_name]
      gcode_file = @gcode_root+"/Job #{job_id}.gcode"
      http       = EM::HttpRequest.new(payload['data']['gcode_url']).get
      
      http.callback{
        file_operation = file_operation_proc(job_id: job_id, gcode_file: gcode_file, http: http, machine_uuid: machine_uuid)
        file_callback  = file_callback_proc(machine: machine, job_id: job_id, gcode_file: gcode_file)
        EM.defer(file_operation, file_callback)
      }
      # http.errback{} # TODO: handle errors
    else
      # TODO: handle errors
    end
  end

  def ping(payload)
    @network.respond_to_ping
  end
  alias_method :websocket_rails_ping, :ping

  def channel_settings(payload)
    @network.channel       = payload['channel']
    @network.channel_token = payload['data']['token']
  end
  alias_method :websocket_rails_channel_token, :channel_settings

private
    def file_operation_proc(job_id: nil, gcode_file: nil, http: nil, machine_uuid: nil)
      Proc.new {
        @network.update_job_state(job_id, machine_uuid, 'download_complete')
        begin
          fd = File.open(gcode_file, 'w+')
          fd.write http.response
        ensure
          fd.close
        end
      }
    end

    def file_callback_proc(machine: nil, job_id: nil, gcode_file: nil)
        Proc.new {
          machine.print_file(job_id, gcode_file)
        }
    end
end

class Machine < EventMachine::Connection
  attr_reader   :connected, :port_name, :port_info, :type, :model, :extruder_count,
                :machine_info, :temperatures, :current_line, :printing, :paused,
                :socket_info, :job_id, :segment

  attr_accessor :uuid

  def initialize(client, port_name)
    super
    @client                     = client
    @port_name                  = port_name
    @unpacker                   = MessagePack::Unpacker.new(symbolize_keys: true)
    @temperatures               = Hash.new
    @client.machines[port_name] = self
    @port_info                  = @client.port_info[port_name].clone
  end

  def update_routines(routines)
    send(action: 'update_routines', data: routines)
  end

  def print_file(job_id, gcode_file)
    @job_id = job_id
    send(action: 'print_file', data: gcode_file)
  end

  def send_commands(commands)
    return nil unless commands.is_a?(Array)
    send(action: 'send_commands', data: commands)
  end

  def segment_completed(data)
    case data
    when 'start_segment'
      @client.network.update_job_state(@job_id, @uuid, 'start_routine_complete')
    when 'print_segment'
      @client.network.update_job_state(@job_id, @uuid, 'print_complete')
    when 'end_segment'
      @client.network.update_job_state(@job_id, @uuid, 'end_routine_complete')
      @job_id = nil
    end
  end

  def info(data)
    @machine_info   ||= data[:machine_info]

    @current_line = data[:current_line]
    @printing     = data[:printing]
    @paused       = data[:paused]
    @segment      = data[:current_segment]
  end

  def temperature(data)
    return nil if !data.is_a?(Hash) || (data.is_a?(Hash) && data.empty?)

    @connected           ||= true
    @temperatures[:bed]    = data[:b]
    @temperatures[:nozzle] = data.select{|key| key.to_s.start_with?('t')}.values
  end

  def server_info(data)
    return nil unless [:version, :pid].all?{|e| data.key?(e)}
    @socket_info = data
  end

  def unbind
    @client.machines.delete(@port_name)
  end

private
    def post_init
      send(action: 'subscribe', data: {type: 'info'})
      send(action: 'subscribe', data: {type: 'temperature'})
      EM::Timer.new(20){ @client.machine_init_check(@port_name) }
    end

    def send(data)
      p [:sending_machine_data, @port_name, data[:action], Time.now]
      send_data(MessagePack.pack(data))
    end

    def receive_data(data)
      @unpacker.feed_each(data){|event| receive_event(event)}
    end

    def receive_event(event)
      return nil unless [:action,:data].all?{|key| event.key?(key)}
      action = event[:action]
      self.__send__(action.to_sym, event[:data]) unless self.public_methods.grep(/\A#{action}\z/).empty?
    end
end

class PrintToClient
  include Helpers

  attr_reader :config, :host, :machines, :uuid_map, :iserial_map, :port_info, :network

  def initialize(host: 'printtopeer.io')
    return nil unless configured?
    @host        = host
    @config      = load_config
    @network     = PtpNetwork.new(self)
    @socket_dir  = "/tmp/PrintToPeer/socks"
    FileUtils::mkdir_p(@socket_dir)
    @machines    = Hash.new
    @uuid_map    = Hash.new
    @iserial_map = Hash.new
    @port_info   = Hash.new
    update_iserial_map
  end

  def connect_first_available(baud)
    first_port           = Dir.glob(['/dev/ttyACM*','/dev/ttyUSB*']).reject{|port| @machines.key?(port_to_name(port))}.first
    return nil if first_port.nil?
    port_name            = port_to_name(first_port)
    connect_machine(port_name, baud)

    EM::Timer.new(15) do
      if @machines.key?(port_name)
        machine = @machines[port_name]
        @network.find_or_create_machine(machine.port_info, port_name)
      end
    end
  end

  def connect_machines(iserials)
    return nil unless iserials.is_a?(Hash)
    update_iserial_map
    connected_iserials = iserials.keys.select{|iserial| @iserial_map.key?(iserial)}

    connected_iserials.each do |iserial|
      port      = @iserial_map[iserial]
      port_name = port_to_name(port)
      values    = iserials[iserial]
      baud      = values['baud']
      uuid      = values['uuid']
      connect_machine(port_name, baud)
      EM::Timer.new(15) do
        if @machines.key?(port_name)
          @machines[port_name].uuid = uuid
          @network.machine_connected(uuid)
          @uuid_map[uuid] = port_name
          p [:connecting_machine_to_ptp, Time.now]
        end
      end
    end
  end

  def machine_init_check(port_name)
    machine = @machines[port_name]
    if !machine.nil? && !machine.connected
      p machine
      @machines.delete(port_name)
      machine.close_connection
      Process.kill("TERM", machine.socket_info[:pid])
    end
  end

  def update_iserial_map
    ports = Dir.glob(['/dev/ttyACM*','/dev/ttyUSB*'])
    return nil if ports.empty?

    iserials  = Hash.new
    port_info = Hash.new

    ports.each do |port|
      dev_info             = `/sbin/udevadm info --query=property --name=#{port}`.split
      iserial              = dev_info.select{|property| property.start_with?('ID_SERIAL_SHORT')}.first.split('=').last
      vid                  = dev_info.select{|property| property.start_with?('ID_VENDOR_ID')}.first.split('=').last
      pid                  = dev_info.select{|property| property.start_with?('ID_MODEL_ID')}.first.split('=').last
      port_name            = port_to_name(port)
      iserials[iserial]    = port_name
      port_info[port_name] = {iserial: iserial, vid: vid, pid: pid}
    end
    
    @iserial_map = iserials
    @port_info   = port_info
  end

private
    def connect_machine(port_name, baud)
      baud               ||= 115200
      socket_location      = "#{@socket_dir}/#{port_name}.sock"

      p [:connecting_machine, port_name, Time.now]

      return nil if @machines.key?(port_name)

      if File.exist?(socket_location)
        EM.connect_unix_domain(socket_location, Machine, self, port_name)
      else
        Process.spawn("sh -c '$HOME/bin/burijji -p /dev/#{port_name} -b #{baud} -s #{socket_location}'")
        EM::Timer.new(10){ EM.connect_unix_domain(socket_location, Machine, self, port_name) }
      end

      return true
    end
end

EM.run {
  Signal.trap('INT')  { EM.stop }
  Signal.trap('TERM') { EM.stop }

  client = PrintToClient.new(host: 'winter.local:3000')
  EM.stop unless client.configured?
}