load '/boot/host.rb'
require 'sinatra'
require 'sinatra/cross_origin'
require 'thin'
require 'yajl/json_gem'
require 'yaml'
require 'net/http'
require 'net/https'
require 'uri'

# PTP Config files
$printtopeer_config = "#{ENV['HOME']}/ptp-config.yml"
$wifi_config = "#{ENV['HOME']}/wifi-config.yml"
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
set :protection, :origin_whitelist => ['http://localhost:3000', 'http://printtopeer.io', 'http://staging.printtopeer.io', 'https://printtopeer.io', 'https://staging.printtopeer.io', HTTP_HOST]
set :allow_origin, :any
set :allow_methods, [:get, :post]

# Set content type
before{ content_type :json }

def enable_filesystem_access
  `sudo mount / -o remount,rw`
end

def disable_filesystem_access
  `sudo sync`
  `sudo mount / -o remount,ro`
end

def configured?
  File.size?($printtopeer_config) ? true : false
end

def get_config
  YAML.load_file($printtopeer_config) if configured?
end

def load_config(file_name)
  return { } unless File.size?(file_name)

  YAML.load_file(file_name)
end

def save_config(file_name, config)
  file_name = '/ro' + file_name if file_name.start_with? '/home'

  enable_filesystem_access
  File.open(file_name, 'w') { |f| f.write config.to_yaml } rescue false
  disable_filesystem_access
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
  hostname = config[:hostname]

  enable_filesystem_access
  `sudo sh -c 'sed -ri s/ptp-server-new/#{hostname}/g /etc/hosts'`
  `sudo sh -c 'echo "#{hostname}" > /etc/hostname'`
  `sudo /etc/init.d/hostname.sh start`
  disable_filesystem_access

  hostname
end

def internet_is_ok?
  `curl https://printtopeer.io`.include? 'Welcome to PrintToPeer'
end

def setup_account
  p [:setup_account, "#{HTTP_HOST}/servers/new"]
  return (p [:setup_failed, :no_internet]) unless internet_is_ok?

  config = load_config $printtopeer_config

  uri = URI.parse("#{HTTP_HOST}/servers/new")
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri)
  request.set_form_data config
  if HTTP_HOST.start_with? "https"
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  p [:setup_account, :make_request]
  response = http.request(request) rescue nil
  return (p [:setup_failed, response.code, response.body]) unless (!response.nil?) && (response.code == '200')
  p [:setup_account, :have_response]

  data = JSON.parse(response.body)

  config[:uuid] = data['uuid']
  config[:password] = data['password']
  config[:hostname] = "ptp-server-#{ data['id'] }"

  save_config $printtopeer_config, config
  set_hostname

  p [:setup_ok]
end

def reboot
  Thread.new do
    `sleep 2`
    `sudo reboot`
  end  
end

# ------------------- wifi -------------------------------
def boot_wifi
  wifi_config = load_config $wifi_config
  ptp_config = load_config $printtopeer_config

  return if wifi_config[:ok] == true && not ptp_config[:uuid].nil?

  connect_wifi :adhoc
end

def test_wifi
  `sleep 2`
  connect_wifi :infrastructure

  config = load_config $wifi_config
  config[:ok] = internet_can_connect?
  save_config $wifi_config, config
end

def internet_can_connect?
  12.times do |t|
    `sleep 5`
    return true if internet_is_ok?
  end

  false
end

def create_wifi_config
  config = load_config $wifi_config
  p [:create_wifi_config, config]
  wpa_supplicant = IO.read("#{ENV['HOME']}/PrintToPi/wifi/infrastructure.conf")
  wpa_supplicant.sub! '$SSID', config[:ssid]
  wpa_supplicant.sub! '$PSK', config[:psk]

  File.open("/home/PrintToPi/wifi/active-infrastructure.conf", 'w') { |f| f.write wpa_supplicant } rescue false
end

def connect_wifi(mode)
  p [:connect_wifi, mode]
  create_wifi_config if mode == :infrastructure

  enable_filesystem_access
  `#{ENV['HOME']}/PrintToPi/wifi/connect_to_#{ mode.to_s }.sh`
  disable_filesystem_access
end

boot_wifi

# ------------------- status_server.rb 2.0 ---------------

get '/test_internet' do
  body({connected: internet_is_ok?}.to_json)
end

get '/scan_wifi' do
  network_lines = `sudo iwlist scan | grep '^ *ESSID' | cut -d '"' -f 2`
  networks = network_lines.split("\n").sort.select { |n| n != 'New PrintToPi' }.select { |n| n != "" }.uniq
  body({:networks => networks}.to_json)
end

get '/status' do
  wifi_config = load_config $wifi_config
  ptp_config = load_config $printtopeer_config

  response = {
    wifi_ok: wifi_config[:ok],
    account_uuid: ptp_config[:uuid]
  }

  body(response.to_json)
end

post '/setup_user' do
  id = params['user_id']
  token = params['new_server_token']

  config = { :user_id => id, :new_server_token => token }
  save_config $printtopeer_config, config
  
  body({:setup => true}.to_json)
end

post '/setup_wifi_and_account' do
  ssid = params['ssid']
  psk = params['psk']

  config = { :ssid => ssid, :psk => psk, :ok => nil }
  save_config $wifi_config, config

  body({:setup => :ok}.to_json)
  Thread.new do
    test_wifi
    setup_account
    connect_wifi :adhoc
  end
end

post '/setup_account' do
  setup_account

  ptp_config = load_config $printtopeer_config
  body({account_uuid: ptp_config[:uuid]}.to_json)
end

post '/reboot' do
  body({reboot: :ok}.to_json)
  reboot  
end

post '/confirm_and_reboot' do
  body({reboot: :ok}.to_json)

  Thread.new do
    connect_wifi :infrastructure
    reboot
  end
end
