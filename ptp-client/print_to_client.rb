

class PrintToClient
  include Helpers

  attr_reader :config, :host, :machines, :uuid_map, :iserial_map, :port_info, :network

  def initialize(host: 'printtopeer.io')
    return nil unless configured?
    @host        = host
    @config      = load_config
    @network     = PtpNetwork.new(self)
    @camera      = Camera.new(@network)
    @socket_dir  = "/tmp/PrintToPeer/socks"
    FileUtils::mkdir_p(@socket_dir)
    @machines    = Hash.new
    @uuid_map    = Hash.new
    @iserial_map = Hash.new
    @port_info   = Hash.new
    update_iserial_map
    send_crash_log
    truncate_log
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
      protocol  = values['protocol']
      uuid      = values['uuid']
      connect_machine(port_name, baud, protocol)
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
      p [:not_connected, machine]
      @machines.delete(port_name)
      machine.close_connection
      Process.kill("TERM", machine.socket_info[:pid])
    end
  end

  def update_iserial_map
    ports = Dir.glob(['/dev/ttyACM*','/dev/ttyUSB*'])

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

  def send_crash_log
    return if @config[:uuid].nil?
    `/home/pi/PrintToPi/bin/upload-log.sh #{@config[:uuid]} #{HTTP_HOST}`
  end

  def truncate_log
    File.truncate('/var/PrintToPeer/logs/ptp_client.log', 0)
  end

private
    def connect_machine(port_name, baud, protocol)
      baud               ||= 115200
      socket_location      = "#{@socket_dir}/#{port_name}.sock"

      p [:connecting_machine, port_name, Time.now]

      return nil if @machines.key?(port_name)

      if File.exist?(socket_location)
        p [:found_socket, socket_location]
        begin
          EM.connect_unix_domain(socket_location, Machine, self, port_name)
          return true
        rescue
          p [:connection_error, :removing_socket]
          File.delete socket_location
        end
      end

      p [:spawn_burijji]
      Process.spawn("$HOME/bin/burijji -p /dev/#{port_name} -b #{baud} -s #{socket_location} -r '#{protocol}'")
      EM::Timer.new(10){ EM.connect_unix_domain(socket_location, Machine, self, port_name) }

      return true
    end
end
