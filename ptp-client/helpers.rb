
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

