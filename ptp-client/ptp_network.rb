
class PtpNetwork
  attr_accessor :reconnect, :channel, :channel_token, :connected
  attr_reader   :client

  def initialize(client)
    @client        = client
    @url           = "#{@client.host}/websocket"
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
          if machine.nil? || !machine.connected
            p [:setup_updates_disconnected]
            @client.uuid_map.delete(uuid)
            machine_disconnected(uuid)
            next
          end
          machine_status = {printing: machine.printing, current_line: machine.current_line, paused: machine.paused, current_segment: machine.segment, job_id: machine.job_id}
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
    
    data = @client.config
    data[:client_version] = 1

    send(action: 'server.authenticate', data: data)
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