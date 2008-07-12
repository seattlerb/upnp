require 'UPnP'
require 'UPnP/SSDP'
require 'UPnP/UUID'
require 'UPnP/root_server'
require 'UPnP/service'
require 'builder'
require 'fileutils'

##
# A device contains sub devices, services and holds information about the
# services provided.  In order to maintain UUIDs across startups, use ::create
# instead of ::new.

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

  def self.add_service_id(service, id)
    SERVICE_IDS[self][service] = id
  end

  ##
  # Loads a device of type +type+ and named +friendly_name+, or creates a new
  # device from +block+ and dumps it.

  def self.create(type, friendly_name, &block)
    klass = const_get type

    device_definition = File.join '~', '.UPnP', type, friendly_name
    device_definition = File.expand_path device_definition

    if File.exist? device_definition then
      open device_definition, 'rb' do |io|
        return Marshal.load(io.read)
      end
    else
      device = klass.new type, friendly_name, &block
      device.dump
      device
    end
  rescue NameError => e
    raise unless e.message =~ /UPnP::Service::#{type}/
    raise Error, "unknown device type #{type}"
  end

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
  # Creates a new device of +type+ using +friendly_name+ with a new name
  # (UUID).  Use #dump and ::create to preserve device names.

  def initialize(type, friendly_name, parent_device = nil)
    @type = type
    @friendly_name = friendly_name
    @sub_devices = []
    @sub_services = []
    @parent = parent_device

    yield self if block_given?

    @name = "uuid:#{UPnP::UUID.generate}"
  end

  ##
  # A device is equal to another device if it has the same name

  def ==(other)
    UPnP::Device === other and @name == other.name
  end

  ##
  # Adds a sub-device of +type+ with +friendly_name+

  def add_device(type, friendly_name = type, &block)
    device = UPnP::Device.new(type, friendly_name, self, &block)
    @sub_devices << device
    device
  end

  ##
  # Adds a UPnP::Service of +type+

  def add_service(type)
    service = UPnP::Service.create self, type
    @sub_services << service
    service
  end

  ##
  # Advertises this device, its sub-devices and services.  Always advertises
  # from the root device.

  def advertise
    addrinfo = Socket.getaddrinfo Socket.gethostname, 0, Socket::AF_INET,
                                  Socket::SOCK_STREAM
    hosts = addrinfo.map { |type, port, host, ip,| ip }.uniq

    Thread.start do
      Thread.abort_on_exception = true

      UPnP::SSDP.new.advertise root_device, @server[:Port], hosts
    end
  end

  ##
  # Returns an XML document describing the root device

  def description
    validate

    description = []

    xml = Builder::XmlMarkup.new :indent => 2, :target => description
    xml.instruct!

    xml.root :xmlns => SCHEMA_URN do
      xml.specVersion do
        xml.major 1
        xml.minor 0
      end

      root_device.device_description xml
    end

    description.join
  end

  ##
  # Adds a description for this device to +xml+

  def device_description(xml)
    validate

    xml.device do
      xml.deviceType       "#{UPnP::DEVICE_SCHEMA_PREFIX}:#{@type}:1"
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
  # The root device

  def root_device
    device = self
    device = device.parent until device.parent.nil?
    device
  end

  ##
  # Starts up this device and gets it running

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
    @server.shutdown
  end

  ##
  # Set up a server

  def setup_server
    @server = UPnP::RootServer.new self

    services.each do |service|
      @server.mount_service service
    end

    @server
  end

  ##
  # URN of this device's type

  def type_urn
    "#{UPnP::DEVICE_SCHEMA_PREFIX}:#{self.class.name.sub(/.*:/, '')}:1"
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

