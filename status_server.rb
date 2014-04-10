require 'sinatra'
require 'sinatra/cross_origin'
require 'thin'
require 'yajl/json_gem'
require 'yaml'

# PTP Config files
$config_file = "#{ENV['HOME']}/ptp-config.yml"
$test_file   = "#{ENV['HOME']}/ptp-connection-test"
$root_disk   = '/dev/mmcblk0'

# Enable cross origin support
configure do
  enable :cross_origin
end

# Configure running settings
set :bind, '0.0.0.0'
set :port, 9090
set :environment, :production
set :server, 'thin'

# Cross origin setings
set :protection, :origin_whitelist => ['http://localhost:3000', 'http://printtopeer.io', 'http://staging.printtopeer.io', 'https://printtopeer.io', 'https://staging.printtopeer.io']
# set :allow_origin, 'https://printtopeer.io'
set :allow_origin, :any
set :allow_methods, [:get, :post]

# Set content type
before{ content_type :json }

def configured?
  File.size?($config_file) ? true : false
end

def get_config
  YAML.load_file($config_file) if configured?
end

def pi_info
  pi_info  = `cat /proc/cmdline`.split
  serial   = pi_info.select{|property| property.start_with?'bcm2708.serial'}[0].split('=')[1]
  revision = pi_info.select{|property| property.start_with?'bcm2708.boardrev'}[0].split('=')[1]
  {revision: revision, serial: serial, sd_card: disk_info, type: :pi}
end

def disk_info
  part_info     = `sudo parted #{$root_disk} -ms unit s p`.split
  sector_size   = part_info.select{|line| line.start_with? $root_disk}[0].split(':')[1].to_i - 1
  root_info     = part_info.select{|line| line.start_with? '2:'}[0].split(':')
  root_start    = root_info[1].to_i
  root_end      = root_info[2].to_i
  sector_info   = {sector_size: sector_size, root_start: root_start, root_end: root_end}
  root_expanded = root_end == sector_size
  disk_size     = sector_size / 925 / 2048
  {root_expanded: root_expanded, disk_size: disk_size, sector_info: sector_info}
end

def expand_root_partition
  sector_info = disk_info[:sector_info]
  root_start  = sector_info[:root_start]
  sector_size = sector_info[:sector_size]
  init_script = '/etc/init.d/resize2fs_once'
  `printf "d\n2\nn\np\n2\n#{root_start}\n#{sector_size}\np\nw\n" | sudo fdisk #{$root_disk}`
  `sudo cp #{ENV['HOME']}/PrintToPi/init/resize2fs_once #{init_script}`
  `sudo chmod +x #{init_script}`
  `sudo update-rc.d resize2fs_once defaults`
  `sync`
end

def set_hostname
  config = get_config
  `sudo sh -c 'sed -ri s/ptp-server-new/#{config['hostname']}/g /etc/hosts'`
  `sudo sh -c 'echo "#{config['hostname']}" > /etc/hostname'`
  `sudo /etc/init.d/hostname.sh start`
  config['hostname']
end

get '/status' do
  {version: '0.1.0', configured: configured?, sys_info: pi_info}.to_json
end

post '/configure' do
  if configured?
    status 409
    body({configured: true, message: 'Server is already configured.'}.to_json)
  else
    required_values = ['password','hostname','uuid']
    values          = params['ptp_info'].select{|key| required_values.include? key}
    required_values.each{|required_value| return(status 400) unless values.has_key? required_value}

    save_result = File.open($config_file, 'w'){|file| file.write(values.to_yaml)} rescue false
    configured  = save_result.is_a?(Numeric)
    File.open($test_file, 'w'){|file| file.write('do test')} rescue nil
    
    body({configured: configured, message: 'Server configuration saved.'}.to_json)
  end
end

post '/finalize-config' do
  if disk_info[:root_expanded]
    status 409
    body({root_expanded: true, message: 'Root partition is already expanded.'}.to_json)
  elsif configured?
    new_hostname = set_hostname
    expand_root_partition
    Process.spawn("sleep 2; sudo reboot")
    body({root_expanded: true, new_hostname: new_hostname, message: 'Expanding root partition and rebooting.'}.to_json)
    # Sinatra::Application.quit! # Sinatra 1.5 needed
  else
    status 409
    body({configured: false, message: 'Server has not yet been configured.'}.to_json)
  end
end
