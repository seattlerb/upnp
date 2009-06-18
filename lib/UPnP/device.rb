require 'UPnP'
require 'UPnP/SSDP'
require 'UPnP/UUID'
require 'UPnP/root_server'
require 'UPnP/service'
require 'fileutils'

require 'nokogiri'

##
# A device contains sub devices, services and holds information about the
# services provided.  If you use ::create, UPnP will maintain device UUIDs
# across startups.
#
# = Creating a UPnP::Device class
#
# A concrete UPnP device looks like this:
#
#   require 'UPnP/device'
#   require 'UPnP/service/content_directory'
#   require 'UPnP/service/connection_manager'
#   
#   class UPnP::Device::MediaServer < UPnP::Device
#     VERSION = '1.0'
#   
#     add_service_id UPnP::Service::ContentDirectory, 'ContentDirectory'
#     add_service_id UPnP::Service::ConnectionManager, 'ConnectorManager'
#   end
#
# Require the sub-services and sub-devices this device requires.  For a
# MediaServer, only a ContentDirectory and ConnectionManager service is
# required.
#
# Subclass UPnP::Device in the UPnP::Device namespace.  UPnP::Device looks in
# its own namespace for various information when instantiating the device.
#
# Add a VERSION constant for your device implementation.  This will be
# reported in device advertisements.
#
# Add the service ids defined in the device specification document.  Not every
# service's type matches up to its service id.
#
# = Instantiating a UPnP::Device
#
# A device instantiation looks like this:
#
#   name = Socket.gethostname.split('.', 2).first
#   
#   device = UPnP::Device.create 'MediaServer', name do |ms|
#     ms.manufacturer = 'Eric Hodel'
#     ms.model_name = 'Media Server'
#   
#     ms.add_service 'ContentDirectory'
#     ms.add_service 'ConnectionManager'
#   end
#
# The first argument to ::create is the device type.  UPnP looks in the
# UPnP::Device namespace for a constant matching this name.  The second is the
# friendly name of the device.  (A hostname-based name seems sane enough for
# this example.)
#
# Various UPnP device settings can be given next.  The manufacturer and model
# name are required by the UPnP specification.  The remainder are attributes
# you can see below.
#
# add_service adds a service of the given type to the device.  UPnP looks in
# the UPnP::Service namespace for a constant matching this name.
#
# #add_device can be used to add a sub-device.  Like ::create, it takes a type
# and friendly name, and yield a block that you must set the manufacturer and
# model name in, in addition to any required sub-devices and sub-services.
#
# = Running a UPnP Device
#
# After instantiating a device it will advertise itself to the network when
# you call #run.
#
# = Creating a UPnP device executable
#
# All the methods you need to create a UPnP device executable are built-in,
# you only need to override option_parser and ::run in your UPnP::Device
# subclass.  See the documentation below for details.
#
# When you're done, create an executable file, require your device file, and
# call ::run on your class:
#
#   #!/usr/bin/env ruby
#   
#   require 'rubygems'
#   require 'UPnP/device/my_device'
#   
#   UPnP::Device::MyDevice.run
#
# Mark it as executable, and you are good to go!

class UPnP::Device

  ##
  # Base device error class

  class Error < UPnP::Error
  end

  ##
  # Raised when device validation fails

  class ValidationError < Error
  end

  ##
  # Maps services for a device to their service ids

  SERVICE_IDS = Hash.new { |h, device| h[device] = {} }

  ##
  # UPnP 1.0 device schema

  SCHEMA_URN = 'urn:schemas-upnp-org:device-1-0'

  ##
  # Short device description for the end user

  attr_accessor :friendly_name

  ##
  # Manufacturer's name

  attr_accessor :manufacturer

  ##
  # Manufacturer's web site

  attr_accessor :manufacturer_url

  ##
  # Long model description for the end user

  attr_accessor :model_description

  ##
  # Model name

  attr_accessor :model_name

  ##
  # Model number

  attr_accessor :model_number

  ##
  # Web site for model

  attr_accessor :model_url

  ##
  # Unique Device Name (UDN), a universally unique identifier for the device
  # whether root or embedded.

  attr_accessor :name

  ##
  # This device's parent device, or nil if it is the root.

  attr_reader :parent

  ##
  # Serial number

  attr_accessor :serial_number

  ##
  # Devices that are immediate children of this device

  attr_accessor :sub_devices

  ##
  # Services that are immediate children of this device

  attr_accessor :sub_services

  ##
  # Type of UPnP device.  Use type_urn for the full URN

  attr_reader :type

  ##
  # Universal Product Code

  attr_accessor :upc

  @option_parser = nil
  @options = nil

  ##
  # Sets the serivceId for +service+ using +domain+ and +id+.  Used in
  # UPnP::Service#description via #description.

  def self.add_service_id(service, id, domain = 'upnp.org')
    SERVICE_IDS[self][service] = "urn:#{domain.tr '.', '-'}:serviceId:#{id}"
  end

  ##
  # Loads a device of type +type+ and named +friendly_name+, or creates a new
  # device from +block+ and dumps it.
  #
  # If a dump exists for the same device type and friendly_name the dump is
  # loaded and used as defaults.  This preserves the device name (UUID) across
  # device restarts.

  def self.create(type, friendly_name, &block)
    klass = const_get type

    device_definition = File.join '~', '.UPnP', type, friendly_name
    device_definition = File.expand_path device_definition

    device = nil

    if File.exist? device_definition then
      open device_definition, 'rb' do |io|
        device = Marshal.load io.read
      end

      yield device if block_given?
    else
      device = klass.new type, friendly_name, &block
    end

    device.dump
    device
  rescue NameError => e
    raise unless e.message =~ /UPnP::Service::#{type}/
    raise Error, "unknown device type #{type}"
  end

  ##
  # True when in debug mode

  def self.debug?
    @debug ||= false
  end

  ##
  # Set debug mode to +value+

  def self.debug=(value)
    @debug = value
  end

  ##
  # Creates an instance of the UPnP::Device subclass named +type+ if it is in
  # the UPnP::Device namespace.

  def self.new(type, *args)
    if UPnP::Device == self then
      klass = begin
                const_get type
              rescue NameError
                self
              end

      klass.new(type, *args)
    else
      super
    end
  end

  ##
  # Creates a new OptionParser and yields the option parser and an options
  # hash for adding a banner or setting device-specific command line
  # arguments.
  #
  # Example:
  #
  #   def self.option_parser
  #     super do |option_parser, options|
  #       options[:name] = Socket.gethostname.split('.', 2).first
  #   
  #       option_parser.banner = <<-EOF
  #   Usage: #{option_parser.program_name} [options]
  #   
  #   Starts a thingy with the stuff...
  #       EOF
  #   
  #       option_parser.on '-n', '--name=NAME', 'Set the name' do |value|
  #         options[:name] = value
  #       end
  #     end
  #   end
  #
  # option_parser automatically provides debug, help and version options.  See
  # also OptionParser in ri for more information on working with OptionParser.

  def self.option_parser
    require 'optparse'

    @options = {}

    @option_parser = OptionParser.new do |option_parser|
      option_parser.version = if const_defined? :VERSION then
                                self::VERSION
                              else
                                UPnP::VERSION
                              end

      option_parser.summary_indent = ' ' * 4

      yield option_parser, @options

      option_parser.program_name = File.basename $0 unless
        option_parser.program_name

      unless option_parser.banner then
        option_parser.banner = "Usage: #{option_parser.program_name} [options]"
      end

      option_parser.separator ''

      option_parser.on('--[no-]debug', 'Provide extra logging') do |value|
        @debug = value
      end
    end
  end

  ##
  # Processes +argv+, but must be overridden in a subclass to
  # create and run the device.
  #
  # Override this in a subclass. The overriden run should super, then #create
  # a device using @options as parsed by option_parser, then call #run on the
  # created device.
  #
  # Example:
  #
  #  def self.run(argv = ARGV)
  #    super
  #  
  #    device = create 'MyDevice' do |md|
  #      md.manufacturer = '...'
  #      # device-specific setup
  #    end
  #  
  #    device.run
  #  end
  #
  # run takes care of invalid arguments and options for you by printing out
  # the help followed by the invalid argument.

  def self.run(argv = ARGV)
    option_parser.parse argv
  rescue OptionParser::InvalidOption, OptionParser::InvalidArgument,
         OptionParser::NeedlessArgument => e
    puts option_parser
    puts
    puts e

    exit 1
  end

  ##
  # Creates a new device of +type+ using +friendly_name+ with a new name
  # (UUID).  Use #dump and ::create to preserve device names.

  def initialize(type, friendly_name, parent_device = nil)
    @type = type
    @friendly_name = friendly_name

    @manufacturer ||= nil
    @manufacturer_url ||= nil

    @model_description ||= nil
    @model_name ||= nil
    @model_number ||= nil
    @model_url ||= nil

    @serial_number ||= nil
    @upc ||= nil

    @sub_devices ||= []
    @sub_services ||= []
    @parent ||= parent_device

    @cache_dir = nil

    yield self if block_given?

    @name ||= "uuid:#{UPnP::UUID.generate}"

    @ssdp = nil
  end

  ##
  # A device is equal to another device if it has the same name

  def ==(other)
    UPnP::Device === other and @name == other.name
  end

  ##
  # Adds a sub-device of +type+ with +friendly_name+.  Devices must have
  # unique types and friendly names.  A sub-device will not be created if it
  # already exists, but the block will be called with the existing sub-device.

  def add_device(type, friendly_name = type, &block)
    sub_device = @sub_devices.find do |d|
      d.type == type and d.friendly_name == friendly_name
    end

    if sub_device then
      yield sub_device if block_given?
      return sub_device
    end

    sub_device = UPnP::Device.new(type, friendly_name, self, &block)
    @sub_devices << sub_device
    sub_device
  end

  ##
  # Adds a UPnP::Service of +type+.  +block+ is passed to the created service
  # for service-specific setup.

  def add_service(type, &block)
    sub_service = @sub_services.find { |s| s.type == type }
    block.call sub_service if sub_service and block
    return sub_service if sub_service

    sub_service = UPnP::Service.create(self, type, &block)
    @sub_services << sub_service
    sub_service
  end

  ##
  # Advertises this device, its sub-devices and services.  Always advertises
  # from the root device.

  def advertise
    addrinfo = Socket.getaddrinfo Socket.gethostname, 0, Socket::AF_INET,
                                  Socket::SOCK_STREAM
    @hosts = addrinfo.map { |type, port, host, ip,| ip }.uniq

    @advertise_thread = Thread.start do
      Thread.abort_on_exception = true

      ssdp.advertise root_device, @server[:Port], @hosts
    end
  end

  ##
  # A directory for storing device-specific persistent data

  def cache_dir
    return @cache_dir if @cache_dir

    @cache_dir = File.join '~', '.UPnP', '_cache', @name
    @cache_dir = File.expand_path @cache_dir

    FileUtils.mkdir_p @cache_dir

    @cache_dir
  end

  ##
  # Returns an XML document describing the root device

  def description
    validate

    builder = Nokogiri::XML::Builder.new do |xml|
      xml.root :xmlns => SCHEMA_URN do
        xml.specVersion do
          xml.major 1
          xml.minor 0
        end

        root_device.device_description xml
      end
    end

    builder.to_xml
  end

  ##
  # Adds a description for this device to +xml+

  def device_description(xml)
    validate

    xml.device do
      xml.deviceType       type_urn
      xml.UDN              @name

      xml.friendlyName     @friendly_name

      xml.manufacturer     @manufacturer
      xml.manufacturerURL  @manufacturer_url  if @manufacturer_url

      xml.modelDescription @model_description if @model_description
      xml.modelName        @model_name
      xml.modelNumber      @model_number      if @model_number
      xml.modelURL         @model_url         if @model_url

      xml.serialNumber     @serial_number     if @serial_number

      xml.UPC              @upc               if @upc

      unless @sub_services.empty? then
        xml.serviceList do
          @sub_services.each do |service|
            service.description(xml)
          end
        end
      end

      unless @sub_devices.empty? then
        xml.deviceList do
          @sub_devices.each do |device|
            device.device_description(xml)
          end
        end
      end
    end
  end

  ##
  # This device and all its sub-devices

  def devices
    [self] + @sub_devices.map do |device|
      device.devices
    end.flatten
  end

  ##
  # Writes this device description into ~/.UPnP so an identically named
  # version can be created on the next load.

  def dump
    device_definition = File.join '~', '.UPnP', @type, @friendly_name
    device_definition = File.expand_path device_definition

    FileUtils.mkdir_p File.dirname(device_definition)

    open device_definition, 'wb' do |io|
      Marshal.dump self, io
    end
  end

  ##
  # Custom Marshal method that only dumps device-specific data.

  def marshal_dump
    [
      @type,
      @friendly_name,
      @sub_devices,
      @sub_services,
      @parent,
      @name,
      @manufacturer,
      @manufacturer_url,
      @model_description,
      @model_name,
      @model_number,
      @model_url,
      @serial_number,
      @upc,
    ]
  end

  ##
  # Custom Marshal method that only loads device-specific data.

  def marshal_load(data)
    @type              = data.shift
    @friendly_name     = data.shift
    @sub_devices       = data.shift
    @sub_services      = data.shift
    @parent            = data.shift
    @name              = data.shift
    @manufacturer      = data.shift
    @manufacturer_url  = data.shift
    @model_description = data.shift
    @model_name        = data.shift
    @model_number      = data.shift
    @model_url         = data.shift
    @serial_number     = data.shift
    @upc               = data.shift
  end

  ##
  # This device's root device

  def root_device
    device = self
    device = device.parent until device.parent.nil?
    device
  end

  ##
  # Starts a root server for the device and advertises it via SSDP.  INT and
  # TERM signal handlers are automatically added, and exit when invoked.  This
  # method won't return until the server is shutdown.

  def run
    setup_server
    advertise

    puts "listening on port #{@server[:Port]}"

    trap 'INT'  do shutdown; exit end
    trap 'TERM' do shutdown; exit end

    @server.start
  end

  ##
  # Retrieves a serviceId for +service+ from the concrete device's service id
  # list

  def service_id(service)
    service_id = service_ids[service.class]

    raise Error, "unknown serviceId for #{service.class}" unless service_id

    service_id
  end

  ##
  # Retrieves the concrete device's service id list.  Requires a SERVICE_IDS
  # constant in the concrete class.

  def service_ids
    SERVICE_IDS[self.class]
  end

  ##
  # All service and sub-services of this device

  def services
    services = @sub_services.dup
    services.push(*@sub_devices.map { |d| d.services })
    services.flatten
  end

  ##
  # Shut down this device

  def shutdown
    @advertise_thread.kill if @advertise_thread

    ssdp.byebye self, @hosts

    @server.shutdown
  end

  ##
  # Creates a root server and attaches this device's services to it.

  def setup_server
    @server = UPnP::RootServer.new self

    services.each do |service|
      @server.mount_service service
    end

    @server
  end

  ##
  # UPnP::SSDP accessor

  def ssdp
    return @ssdp if @ssdp

    @ssdp = UPnP::SSDP.new
    @ssdp.log = @server[:Logger]

    @ssdp
  end

  ##
  # URN of this device's type

  def type_urn
    "#{UPnP::DEVICE_SCHEMA_PREFIX}:#{@type}:1"
  end

  ##
  # Raises a ValidationError if any of the required fields are nil

  def validate
    raise ValidationError, 'friendly_name missing' if @friendly_name.nil?
    raise ValidationError, 'manufacturer missing' if @manufacturer.nil?
    raise ValidationError, 'model_name missing' if @model_name.nil?
  end

  ##
  # The version of this device, or the UPnP version if the device did not
  # define it

  def version
    if self.class.const_defined? :VERSION then
      self.class::VERSION
    else
      UPnP::VERSION
    end
  end

end

