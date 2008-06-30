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
#   ssdp.listen
#
# To discover all devices and services:
#
#  ssdp = SSDP.new
#  ssdp.search
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
      date + max_age
    end

    ##
    # True if this advertisement has expired

    def expired?
      Time.now > expiration
    end

  end

  ##
  # Holds information about a NOTIFY message

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
    # Type of the advertised service or device

    attr_reader :type

    ##
    # Server name and version of the advertised service or device

    attr_reader :server

    ##
    # Advertisement sub-type

    attr_reader :sub_type

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
    # Creates a new Notification

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
  # Port to use for SSDP searching and listening

  attr_accessor :port

  ##
  # Queue accessor for tests

  attr_accessor :queue # :nodoc:

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

    @listener = nil
    @queue = Queue.new
  end

  ##
  # Discovers UPnP devices sending NOTIFY broadcasts.
  #
  # If given a block, yields each Notification as it is received and never
  # returns.  Otherwise, discover waits for timeout seconds and returns all
  # notifications received in that time.

  def discover
    membership = IPAddr.new(@broadcast).hton + IPAddr.new('0.0.0.0').hton

    @socket ||= UDPSocket.new

    @socket.setsockopt Socket::IPPROTO_IP, Socket::IP_TTL, [@ttl].pack('i')
    @socket.setsockopt Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, membership

    @socket.bind Socket::INADDR_ANY, @port

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
        response = @socket.recvfrom(1024).first

        begin
          @queue << parse(response)
        rescue
          puts $!.message
          puts $!.backtrace
        end
      end
    end
  end

  ##
  # Returns a Notification or Response created from +response+.

  def parse(response)
    case response
    when /\ANOTIFY/ then
      Notification.parse response
    when /\AHTTP/ then
      Response.parse response
    else
      raise Error, "Unknown response #{response[/\A.*$/]}"
    end
  end

  ##
  # Broadcasts M-SEARCH requests looking for +targets+.  Waits timeout seconds
  # for responses then returns the collected responses.
  #
  # Supply no arguments to search for all devices and services.
  #
  # Supply +:root+ to search for root devices only.
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
    @socket ||= UDPSocket.new

    @socket.setsockopt Socket::IPPROTO_IP, Socket::IP_TTL, [@ttl].pack('i')

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
  # Builds and sends an M-SEARCH request looking for +search_target+.

  def send_search(search_target)
    http_request = <<HTTP_REQUEST
M-SEARCH * HTTP/1.1\r
HOST: #{@broadcast}:#{@port}\r
MAN: "ssdp:discover"\r
MX: #{@timeout}\r
ST: #{search_target}\r
\r
HTTP_REQUEST

    @socket.send http_request, 0, @broadcast, @port
  end

  ##
  # Stops and clears the listen thread.

  def stop_listening
    @listener.kill if @listener
    @queue = Queue.new
    @listener = nil
  end

end

