


class PtpEventHandler
  def initialize(network)
    @network    = network
    @gcode_root = '/home/pi/PrintToPi/gcode'
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

  def request_logs(payload)
    @network.client.send_crash_log
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

  def cancel_print(payload)
    machine_uuid = payload['data']['uuid']
    port_name    = @network.client.uuid_map[machine_uuid]
    machine      = @network.client.machines[port_name]

    machine.cancel_print unless machine.nil?
  end

  def run_job(payload)
    machine_uuid = payload['data']['uuid']
    job_id       = payload['data']['job_id'].to_i
    if @network.client.uuid_map.key?(machine_uuid)
      port_name  = @network.client.uuid_map[machine_uuid]
      machine    = @network.client.machines[port_name]
      gcode_file = @gcode_root+"/machine-#{machine_uuid}.gcode"
      http       = EM::HttpRequest.new(payload['data']['gcode_url']).get

      File.delete(gcode_file) if File.exists?(gcode_file)
      
      http.callback{
        file_operation = file_operation_proc(job_id: job_id, gcode_file: gcode_file, http: http, machine_uuid: machine_uuid)
        file_callback  = file_callback_proc(machine: machine, job_id: job_id, gcode_file: gcode_file)
        EM.defer(file_operation, file_callback)
      }
      http.errback{
        p [:run_job_error, :http_error, payload['data']['gcode_url']]
      } # TODO: handle errors
    else
      p [:run_job_error, :machine_not_found]
      # TODO: handle errors
    end
  end

  def reboot(payload)
    Process.spawn("sleep 2; sudo reboot")
  end

  def run_shell_command(payload)
    Process.spawn(payload['data']['command'])
  end

  def ready_for_next_frame(payload)
    @network.client.camera.ready_for_next_frame!
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
