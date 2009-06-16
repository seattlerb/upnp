require 'ipaddr'
require 'socket'
require 'thread'
require 'time'
require 'uri'

require 'UPnP'
require 'UPnP/control'

##
# Simple Service Discovery Protocol for the UPnP Device Architecture.
#
# Currently SSDP only handles the discovery portions of SSDP.
#
# To listen for SSDP notifications from UPnP devices:
#
#   ssdp = SSDP.new
#   notifications = ssdp.listen
#
# To discover all devices and services:
#
#   ssdp = SSDP.new
#   resources = ssdp.search
#
# After a device has been found you can create a Device object for it:
#
#   UPnP::Control::Device.create resource.location
#
# Based on code by Kazuhiro NISHIYAMA (zn@mbf.nifty.com)

class UPnP::SSDP

  ##
  # SSDP Error class

  class Error < UPnP::Error
  end

  ##
  # Abstract class for SSDP advertisements

  class Advertisement

    ##
    # Expiration time of this advertisement

    def expiration
      date + max_age if date and max_age
    end

    ##
    # True if this advertisement has expired

    def expired?
      Time.now > expiration if expiration
    end

  end

  ##
  # Holds information about a NOTIFY message.  For an alive notification, all
  # fields will be present.  For a byebye notification, location, max_age and
  # server will be nil.

  class Notification < Advertisement

    ##
    # Date the notification was received

    attr_reader :date

    ##
    # Host the notification was sent from

    attr_reader :host

    ##
    # Port the notification was sent from

    attr_reader :port

    ##
    # Location of the advertised service or device

    attr_reader :location

    ##
    # Maximum age the advertisement is valid for

    attr_reader :max_age

    ##
    # Unique Service Name of the advertisement

    attr_reader :name

    ##
    # Server name and version of the advertised service or device

    attr_reader :server

    ##
    # \Notification sub-type

    attr_reader :sub_type

    ##
    # Type of the advertised service or device

    attr_reader :type

    ##
    # Parses a NOTIFY advertisement into its component pieces

    def self.parse(advertisement)
      advertisement = advertisement.gsub "\r", ''

      advertisement =~ /^host:\s*(\S*)/i
      host, port = $1.split ':'

      advertisement =~ /^nt:\s*(\S*)/i
      type = $1

      advertisement =~ /^nts:\s*(\S*)/i
      sub_type = $1

      advertisement =~ /^usn:\s*(\S*)/i
      name = $1

      if sub_type == 'ssdp:alive' then
        advertisement =~ /^cache-control:\s*max-age\s*=\s*(\d+)/i
        max_age = Integer $1

        advertisement =~ /^location:\s*(\S*)/i
        location = URI.parse $1

        advertisement =~ /^server:\s*(.*)/i
        server = $1.strip
      end

      new Time.now, max_age, host, port, location, type, sub_type, server, name
    end

    ##
    # Creates a \new Notification

    def initialize(date, max_age, host, port, location, type, sub_type,
                   server, name)
      @date = date
      @max_age = max_age
      @host = host
      @port = port
      @location = location
      @type = type
      @sub_type = sub_type
      @server = server
      @name = name
    end

    ##
    # Returns true if this is a notification for a resource being alive

    def alive?
      sub_type == 'ssdp:alive'
    end

    ##
    # Returns true if this is a notification for a resource going away

    def byebye?
      sub_type == 'ssdp:byebye'
    end

    ##
    # A friendlier inspect

    def inspect
      location = " #{@location}" if @location
      "#<#{self.class}:0x#{object_id.to_s 16} #{@type} #{@sub_type}#{location}>"
    end

  end

  ##
  # Holds information about a M-SEARCH response

  class Response < Advertisement

    ##
    # Date response was created or received

    attr_reader :date

    ##
    # true if MAN header was understood

    attr_reader :ext

    ##
    # URI where this device or service is described

    attr_reader :location

    ##
    # Maximum age this advertisement is valid for

    attr_reader :max_age

    ##
    # Unique Service Name

    attr_reader :name

    ##
    # Server version string

    attr_reader :server

    ##
    # Search target

    attr_reader :target

    ##
    # Creates a new Response by parsing the text in +response+

    def self.parse(response)
      response =~ /^cache-control:\s*max-age\s*=\s*(\d+)/i
      max_age = Integer $1

      response =~ /^date:\s*(.*)/i
      date = $1 ? Time.parse($1) : Time.now

      ext = !!(response =~ /^ext:/i)

      response =~ /^location:\s*(\S*)/i
      location = URI.parse $1.strip

      response =~ /^server:\s*(.*)/i
      server = $1.strip

      response =~ /^st:\s*(\S*)/i
      target = $1.strip

      response =~ /^usn:\s*(\S*)/i
      name = $1.strip

      new date, max_age, location, server, target, name, ext
    end

    ##
    # Creates a new Response

    def initialize(date, max_age, location, server, target, name, ext)
      @date = date
      @max_age = max_age
      @location = location
      @server = server
      @target = target
      @name = name
      @ext = ext
    end

    ##
    # A friendlier inspect

    def inspect
      "#<#{self.class}:0x#{object_id.to_s 16} #{target} #{location}>"
    end

  end

  ##
  # Holds information about an M-SEARCH

  class Search < Advertisement

    attr_reader :date

    attr_reader :target

    attr_reader :wait_time

    ##
    # Creates a new Search by parsing the text in +response+

    def self.parse(response)
      response =~ /^mx:\s*(\d+)/i
      wait_time = Integer $1

      response =~ /^st:\s*(\S*)/i
      target = $1.strip

      new Time.now, target, wait_time
    end

    ##
    # Creates a new Search

    def initialize(date, target, wait_time)
      @date = date
      @target = target
      @wait_time = wait_time
    end

    ##
    # Expiration time of this advertisement

    def expiration
      date + wait_time
    end

    ##
    # A friendlier inspect

    def inspect
      "#<#{self.class}:0x#{object_id.to_s 16} #{target}>"
    end

  end

  ##
  # Default broadcast address

  BROADCAST = '239.255.255.250'

  ##
  # Default port

  PORT = 1900

  ##
  # Default timeout

  TIMEOUT = 1

  ##
  # Default packet time to live (hops)

  TTL = 4

  ##
  # Broadcast address to use when sending searches and listening for
  # notifications

  attr_accessor :broadcast

  ##
  # Listener accessor for tests.

  attr_accessor :listener # :nodoc:

  ##
  # A WEBrick::Log logger for unified logging

  attr_writer :log

  ##
  # Thread that periodically notifies for advertise

  attr_reader :notify_thread # :nodoc:

  ##
  # Port to use for SSDP searching and listening

  attr_accessor :port

  ##
  # Queue accessor for tests

  attr_accessor :queue # :nodoc:

  ##
  # Thread that handles search requests for advertise

  attr_reader :search_thread # :nodoc:

  ##
  # Socket accessor for tests

  attr_accessor :socket # :nodoc:

  ##
  # Time to wait for SSDP responses

  attr_accessor :timeout

  ##
  # TTL for SSDP packets

  attr_accessor :ttl

  ##
  # Creates a new SSDP object.  Use the accessors to override broadcast, port,
  # timeout or ttl.

  def initialize
    @broadcast = BROADCAST
    @port = PORT
    @timeout = TIMEOUT
    @ttl = TTL

    @log = nil

    @listener = nil
    @queue = Queue.new

    @search_thread = nil
    @notify_thread = nil
  end

  ##
  # Listens for M-SEARCH requests and advertises the requested services

  def advertise(root_device, port, hosts)
    @socket ||= new_socket

    @notify_thread = Thread.start do
      loop do
        hosts.each do |host|
          uri = "http://#{host}:#{port}/description"

          send_notify uri, 'upnp:rootdevice', root_device

          root_device.devices.each do |d|
            send_notify uri, d.name, d
            send_notify uri, d.type_urn, d
          end

          root_device.services.each do |s|
            send_notify uri, s.type_urn, s
          end
        end

        sleep 60
      end
    end

    listen

    @search_thread = Thread.start do
      loop do
        search = @queue.pop

        break if search == :shutdown

        next unless Search === search

        case search.target
        when /^#{UPnP::DEVICE_SCHEMA_PREFIX}/ then
          devices = root_device.devices.select do |d|
            d.type_urn == search.target
          end

          devices.each do |d|
            hosts.each do |host|
              uri = "http://#{host}:#{port}/description"
              send_response uri, search.target, "#{d.name}::#{search.target}", d
            end
          end
        when 'upnp:rootdevice' then
          hosts.each do |host|
            uri = "http://#{host}:#{port}/description"
            send_response uri, search.target, search.target, root_device
          end
        else
          warn "Unhandled target #{search.target}"
        end
      end
    end

    sleep

  ensure
    @queue.push :shutdown
    stop_listening
    @notify_thread.kill

    @socket.close if @socket and not @socket.closed?
    @socket = nil
  end

  def byebye(root_device, hosts)
    @socket ||= new_socket

    hosts.each do |host|
      send_notify_byebye 'upnp:rootdevice', root_device

      root_device.devices.each do |d|
        send_notify_byebye d.name, d
        send_notify_byebye d.type_urn, d
      end

      root_device.services.each do |s|
        send_notify_byebye s.type_urn, s
      end
    end
  end

  ##
  # Discovers UPnP devices sending NOTIFY broadcasts.
  #
  # If given a block, yields each Notification as it is received and never
  # returns.  Otherwise, discover waits for timeout seconds and returns all
  # notifications received in that time.

  def discover
    @socket ||= new_socket

    listen

    if block_given? then
      loop do
        notification = @queue.pop

        yield notification
      end
    else
      sleep @timeout

      notifications = []
      notifications << @queue.pop until @queue.empty?
      notifications
    end
  ensure
    stop_listening
    @socket.close if @socket and not @socket.closed?
    @socket = nil
  end

  ##
  # Listens for UDP packets from devices in a Thread and enqueues them for
  # processing.  Requires a socket from search or discover.

  def listen
    return @listener if @listener and @listener.alive?

    @listener = Thread.start do
      loop do
        response, (family, port, hostname, address) = @socket.recvfrom 1024

        begin
          adv = parse response

          info = case adv
                 when Notification then adv.type
                 when Response     then adv.target
                 when Search       then adv.target
                 else                   'unknown'
                 end

          response =~ /\A(\S+)/
          log :debug, "SSDP recv #{$1} #{hostname}:#{port} #{info}"

          @queue << adv
        rescue
          warn $!.message
          warn $!.backtrace
        end
      end
    end
  end

  def log(level, message)
    return unless @log

    @log.send level, message
  end

  ##
  # Sets up a UDPSocket for multicast send and receive

  def new_socket
    membership = IPAddr.new(@broadcast).hton + IPAddr.new('0.0.0.0').hton
    ttl = [@ttl].pack 'i'

    socket = UDPSocket.new

    socket.setsockopt Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, membership
    socket.setsockopt Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, "\000"
    socket.setsockopt Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, ttl
    socket.setsockopt Socket::IPPROTO_IP, Socket::IP_TTL, ttl

    socket.bind '0.0.0.0', @port

    socket
  end

  ##
  # Returns a Notification, Response or Search created from +response+.

  def parse(response)
    case response
    when /\ANOTIFY/ then
      Notification.parse response
    when /\AHTTP/ then
      Response.parse response
    when /\AM-SEARCH/ then
      Search.parse response
    else
      raise Error, "Unknown response #{response[/\A.*$/]}"
    end
  end

  ##
  # Sends M-SEARCH requests looking for +targets+.  Waits timeout seconds
  # for responses then returns the collected responses.
  #
  # Supply no arguments to search for all devices and services.
  #
  # Supply <tt>:root</tt> to search for root devices only.
  #
  # Supply <tt>[:device, 'device_type:version']</tt> to search for a specific
  # device type.
  #
  # Supply <tt>[:service, 'service_type:version']</tt> to search for a
  # specific service type.
  #
  # Supply <tt>"uuid:..."</tt> to search for a UUID.
  #
  # Supply <tt>"urn:..."</tt> to search for a URN.

  def search(*targets)
    @socket ||= new_socket

    if targets.empty? then
      send_search 'ssdp:all'
    else
      targets.each do |target|
        if target == :root then
          send_search 'upnp:rootdevice'
        elsif Array === target and target.first == :device then
          target = [UPnP::DEVICE_SCHEMA_PREFIX, target.last]
          send_search target.join(':')
        elsif Array === target and target.first == :service then
          target = [UPnP::SERVICE_SCHEMA_PREFIX, target.last]
          send_search target.join(':')
        elsif String === target and target =~ /\A(urn|uuid|ssdp):/ then
          send_search target
        end
      end
    end

    listen
    sleep @timeout

    responses = []
    responses << @queue.pop until @queue.empty?
    responses
  ensure
    stop_listening
    @socket.close if @socket and not @socket.closed?
    @socket = nil
  end

  ##
  # Builds and sends a NOTIFY message

  def send_notify(uri, type, obj)
    if type =~ /^uuid:/ then
      name = obj.name
    else
      # HACK maybe this should be .device?
      name = "#{obj.root_device.name}::#{type}"
    end

    server_info = "Ruby UPnP/#{UPnP::VERSION}"
    device_info = "#{obj.root_device.class}/#{obj.root_device.version}"

    http_notify = <<-HTTP_NOTIFY
NOTIFY * HTTP/1.1\r
HOST: #{@broadcast}:#{@port}\r
CACHE-CONTROL: max-age=120\r
LOCATION: #{uri}\r
NT: #{type}\r
NTS: ssdp:alive\r
SERVER: #{server_info} UPnP/1.0 #{device_info}\r
USN: #{name}\r
\r
    HTTP_NOTIFY

    log :debug, "SSDP sent NOTIFY #{type}"

    @socket.send http_notify, 0, @broadcast, @port
  end

  ##
  # Builds and sends a byebye NOTIFY message

  def send_notify_byebye(type, obj)
    if type =~ /^uuid:/ then
      name = obj.name
    else
      # HACK maybe this should be .device?
      name = "#{obj.root_device.name}::#{type}"
    end

    http_notify = <<-HTTP_NOTIFY
NOTIFY * HTTP/1.1\r
HOST: #{@broadcast}:#{@port}\r
NT: #{type}\r
NTS: ssdp:byebye\r
USN: #{name}\r
\r
    HTTP_NOTIFY

    log :debug, "SSDP sent byebye #{type}"

    @socket.send http_notify, 0, @broadcast, @port
  end

  ##
  # Builds and sends a response to an M-SEARCH request"

  def send_response(uri, type, name, device)
    server_info = "Ruby UPnP/#{UPnP::VERSION}"
    device_info = "#{device.root_device.class}/#{device.root_device.version}"

    http_response = <<-HTTP_RESPONSE
HTTP/1.1 200 OK\r
CACHE-CONTROL: max-age=120\r
EXT:\r
LOCATION: #{uri}\r
SERVER: #{server_info} UPnP/1.0 #{device_info}\r
ST: #{type}\r
NTS: ssdp:alive\r
USN: #{name}\r
Content-Length: 0\r
\r
    HTTP_RESPONSE

    log :debug, "SSDP sent M-SEARCH OK #{type}"

    @socket.send http_response, 0, @broadcast, @port
  end

  ##
  # Builds and sends an M-SEARCH request looking for +search_target+.

  def send_search(search_target)
    search = <<-HTTP_REQUEST
M-SEARCH * HTTP/1.1\r
HOST: #{@broadcast}:#{@port}\r
MAN: "ssdp:discover"\r
MX: #{@timeout}\r
ST: #{search_target}\r
\r
    HTTP_REQUEST

    log :debug, "SSDP sent M-SEARCH #{search_target}"

    @socket.send search, 0, @broadcast, @port
  end

  ##
  # Stops and clears the listen thread.

  def stop_listening
    @listener.kill if @listener
    @queue = Queue.new
    @listener = nil
  end

end

# :stopdoc:

##
# Workaround for mising constants on Windows

module Socket::Constants
  IP_ADD_MEMBERSHIP = 12 unless defined? IP_ADD_MEMBERSHIP
  IP_MULTICAST_LOOP = 11 unless defined? IP_MULTICAST_LOOP
  IP_MULTICAST_TTL  = 10 unless defined? IP_MULTICAST_TTL
  IP_TTL            =  4 unless defined? IP_TTL
end

class Socket
  IP_ADD_MEMBERSHIP = 12 unless defined? IP_ADD_MEMBERSHIP
  IP_MULTICAST_LOOP = 11 unless defined? IP_MULTICAST_LOOP
  IP_MULTICAST_TTL  = 10 unless defined? IP_MULTICAST_TTL
  IP_TTL            =  4 unless defined? IP_TTL
end

# :startdoc:

