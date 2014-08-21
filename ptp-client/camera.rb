require 'base64'

class Camera

  def initialize(network)
    @network = network
    @frame_dir = "/tmp/PrintToPeer/camera_frames"
    @frame_path = "#{@frame_dir}/frame.jpg"

    stream_camera_frames if camera_is_installed?
  end 

  def camera_is_installed?
    `sudo vcgencmd get_camera`.include? 'detected=1'
  end

  def stream_camera_frames
    FileUtils::mkdir_p(@frame_dir)

    @pid = `pgrep raspifastcamd`

    if @pid.empty?
      IO.popen("sudo bash -c '/home/pi/PrintToPi/bin/raspifastcamd -w 320 -h 240 -q 10 -o #{@frame_path}'")
      sleep 1
      @pid = `pgrep raspifastcamd`
    end

    EM::PeriodicTimer.new(0.25) { stream_camera_frame }
  end

  def stream_camera_frame
    send_frame @frame_path if File.exist? @frame_path
    request_next_frame
  end

  def send_frame(frame)
    GC.start
    @network.camera_frame Base64.encode64(File.read(frame))
    File.delete(frame)
  end

  def request_next_frame
    `sudo kill -s SIGUSR1 #{@pid}`
  end

end
