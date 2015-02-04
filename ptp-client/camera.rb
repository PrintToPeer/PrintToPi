require 'base64'

MINIMUM_FRAME_INTERVAL = 0.125

class Camera

  def initialize(network)
    @network = network
    @frame_dir = "/tmp/PrintToPeer/camera_frames"
    @frame_path = "#{@frame_dir}/frame.jpg"

    @last_frame_sent_at = nil

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

    EM::PeriodicTimer.new(0.125) { stream_camera_frame }
  end

  def stream_camera_frame
    return unless server_is_ready_for_frame

    send_frame @frame_path if File.exist? @frame_path
    request_next_frame
    
    @last_frame_sent_at = Time.now
  end

  def send_frame(frame)
    GC.start
    @network.camera_frame Base64.encode64(File.read(frame))
    File.delete(frame)
  end

  def ready_for_next_frame!
    @ready_to_send_frame_at = Time.now
  end

  def request_next_frame
    `sudo kill -s SIGUSR1 #{@pid}`
  end

private

  def server_is_ready_for_frame
    return false if @ready_to_send_frame_at.nil?
    return false if @ready_to_send_frame_at > Time.now
    return false if (!@last_frame_sent_at.nil?) && (Time.now - @last_frame_sent_at) < MINIMUM_FRAME_INTERVAL

    @ready_to_send_frame_at = nil
    return true
  end

end
