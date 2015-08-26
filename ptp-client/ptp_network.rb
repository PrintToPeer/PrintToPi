LOG_ALL_MESSAGES = false

class PtpNetwork
  attr_accessor :reconnect, :channel, :channel_token, :connected
  attr_reader   :client

  def initialize(client)
    @last_receipt  = nil
    @client        = client
    @url           = "#{@client.host}/websocket"
    @reconnect     = true
    @event_handler = PtpEventHandler.new(self)
    @websocket     = Faye::WebSocket::Client.new(@url)
    setup_ws_callbacks
    setup_updates
  end

  def camera_frame(frame)
    send(action: 'server.camera_frame', data: {frame: frame}) if @connected
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
  
  def reconnect_if_incoming_messages_are_being_dropped
    # Bug: Sometimes the network connection gets wedged where the Pi doesn't receive any
    # messages from the server, but the server thinks it's still connected. Everything appears 
    # offline until you try a print or the maintenance console, at which point things break.
    # 
    # Solution: Do a client-side reconnect if we haven't gotten a message from the server in 
    # the last 60 seconds (we're supposed to get a ping every ~10 seconds)
    return if @last_receipt.nil?
    
    time_since_last_receipt = Time.now - @last_receipt
    return unless time_since_last_receipt > 60

    p [:no_incoming_messages, Time.now, :last_message, @last_receipt]    
    @websocket.close
  end

  def setup_updates
    EM::PeriodicTimer.new(1) do
      if @connected
        reconnect_if_incoming_messages_are_being_dropped
        
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
        update_data[:client_version]  = CLIENT_VERSION

        send(action: 'server.update_data', data: update_data) unless update_data.empty?
      end
    end
  end

  def authenticate
    @connected = true
    
    data = @client.config

    send(action: 'server.authenticate', data: data)
  end

  def send(id: rand(1..100000), action: nil, channel: false, data: Hash.new)
    return unless @connected
    if channel
      response = [action, id: id, channel: @channel, data: data, token: @channel_token]
    else
      response = [action, id: id, channel: nil, data: data, token: nil]
    end
    p [:send, Time.now, response.to_json[0..300]] if LOG_ALL_MESSAGES
    @websocket.send @binary ? response.to_msgpack.bytes : response.to_json
  end

  def receive(event)
    @last_receipt = Time.now
    @binary = true if event.data.is_a?(Array)
    event  = event.data.to_event
    action = event[:action].sub('.', '_') rescue event[:action].to_s.sub('.', '_')
    @event_handler.__send__(action.to_sym, event[:payload]) unless @event_handler.public_methods.grep(/\A#{action}\z/).empty?
    p [:receive, Time.now, event] if LOG_ALL_MESSAGES
  end

  def reconnect
    @last_receipt = nil
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
