
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

  def cancel_print
    @job_id = nil
    send(action: 'stop_print', data: '')
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

  def disconnected(data)
    p [:machine_disconnected, @port_name]
    @connected = false
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
