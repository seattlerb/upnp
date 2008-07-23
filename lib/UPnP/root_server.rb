require 'UPnP'
require 'webrick'

##
# Master WEBrick server that publishes a root device's sub-devices and
# services for consumption by a UPnP control device.
#
# A root server is created automatiaclly for a device when you call #run on
# your device instance.

class UPnP::RootServer < WEBrick::HTTPServer

  ##
  # The WEBrick logger

  attr_reader :logger # :nodoc:

  ##
  # This server's root UPnP device

  attr_reader :root_device

  ##
  # This server's SCPDs

  attr_reader :scpds # :nodoc:

  ##
  # Creates a new UPnP web server with +root_device+

  def initialize(root_device)
    @root_device = root_device

    server_info = "RubyUPnP/#{UPnP::VERSION}"
    device_info = "Ruby#{root_device.type}/#{root_device.version}"
    @server_version = [server_info, 'UPnP/1.0', device_info].join ' '

    @scpds = {}

    level = if @root_device.class.debug? then
              WEBrick::BasicLog::DEBUG
            else
              WEBrick::BasicLog::FATAL
            end

    @logger = WEBrick::Log.new $stderr, level

    super :Logger => @logger, :Port => 0

    mount_proc '/description', method(:description)
    mount_proc '/',            method(:root)
  end

  ##
  # Handler for the root device description

  def description(req, res)
    raise WEBrick::HTTPStatus::NotFound, "`#{req.path}' not found." unless
      req.path == '/description'

    res['content-type'] = 'text/xml'
    res.body << @root_device.description
  end

  ##
  # Mounts WEBrick::HTTPServer +server+ at +path+

  def mount_server(path, server)
    server.config[:Logger] = @logger

    mount_proc path do |req, res|
      server.service req, res

    end
  end

  ##
  # Mounts the appropriate paths for +service+ in this service

  def mount_service(service)
    mount_server service.control_url, service.server

    service.mount_extra self

    @scpds[service.scpd_url] = service
    mount_proc service.scpd_url, method(:scpd)
  end

  ##
  # A generic display page for the webserver root

  def root(req, res)
    raise WEBrick::HTTPStatus::NotFound, "`#{req.path}' not found." unless
      req.path == '/'

    res['content-type'] = 'text/html'

    devices = @root_device.devices[1..-1].map do |d|
      "<li>#{d.friendly_name} - #{d.type}"
    end.join "\n"

    services = @root_device.services.map do |s|
      "<li>#{s.type}"
    end.join "\n"

    res.body = <<-EOF
<title>#{@root_device.friendly_name} - #{@root_device.type}</title>

<p>Devices:

<ul>
#{devices}
</ul>

<p>Services:

<ul>
#{services}
</ul>
    EOF
  end

  ##
  # Handler for a service control protocol description request

  def scpd(req, res)
    service = @scpds[req.path]
    raise WEBrick::HTTPStatus::NotFound, "`#{req.path}' not found." unless
      service

    res['content-type'] = 'text/xml'
    res.body << service.scpd
  end

  def service(req, res)
    super

    res['Server'] = @server_version
    res['EXT'] = ''
  end

end

