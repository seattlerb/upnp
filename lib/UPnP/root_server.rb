require 'UPnP'
require 'webrick'

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

    @scpds = {}

    @logger = WEBrick::Log.new '/dev/null', WEBrick::BasicLog::FATAL

    super :Logger => @logger, :Port => 0

    mount_proc '/description', method(:description)
  end

  ##
  # Returns the root device description

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

    mount_proc path do |req, res| server.service req, res end
  end

  ##
  # Mounts the appropriate paths for +service+ in this service

  def mount_service(service)
    mount_server service.control_url, service.server

    @scpds[service.scpd_url] = service
    mount_proc service.scpd_url, method(:scpd)
  end

  ##
  # Handles a request for an SCPD

  def scpd(req, res)
    service = @scpds[req.path]
    raise WEBrick::HTTPStatus::NotFound, "`#{req.path}' not found." unless
      service

    res['content-type'] = 'text/xml'
    res.body << service.scpd
  end

end

