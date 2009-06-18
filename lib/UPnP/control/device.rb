require 'open-uri'
require 'uri'

require 'nokogiri'

require 'UPnP'
require 'UPnP/SSDP'
require 'UPnP/control/service'

##
# A device on a UPnP control point.
#
# A Device holds information about a device and its associated sub-devices and
# services.
#
# Devices should be created using ::create instead of ::new.  This allows a
# subclass of Device to be automatically instantiated.
#
# When creating a device subclass, it must have a URN_version constant set to
# the schema URN for that version.
#
# For details on UPnP devices, see http://www.upnp.org/resources/documents.asp

class UPnP::Control::Device

  ##
  # All embedded devices

  attr_reader :devices

  ##
  # Short device description for the end user

  attr_reader :friendly_name

  ##
  # Manufacturer's name

  attr_reader :manufacturer

  ##
  # Manufacturer's web site

  attr_reader :manufacturer_url

  ##
  # Long model description for the end user

  attr_reader :model_description

  ##
  # Model name

  attr_reader :model_name

  ##
  # Model number

  attr_reader :model_number

  ##
  # Web site for model

  attr_reader :model_url

  ##
  # Unique Device Name (UDN), a universally unique identifier for the device
  # whether root or embedded.

  attr_reader :name

  ##
  # URL for device control via a browser

  attr_reader :presentation_url

  ##
  # Serial number

  attr_reader :serial_number

  ##
  # All services provided by this device and its sub-devices.

  attr_reader :services

  ##
  # Devices embedded directly into this device.

  attr_reader :sub_devices

  ##
  # Services provided directly by this device.

  attr_reader :sub_services

  ##
  # Type of UPnP device (URN)

  attr_reader :type

  ##
  # Universal Product Code

  attr_reader :upc

  ##
  # Base URL for this device

  attr_reader :url

  ##
  # If a concrete class exists for +description+ it is used to instantiate the
  # device, otherwise a concrete class is created subclassing Device and
  # used.

  def self.create(device_url)
    description = Nokogiri::XML open(device_url)
    url = device_url + '/'

    type = description.at('root > device > deviceType').text
    klass_name = type.sub(/#{UPnP::DEVICE_SCHEMA_PREFIX}:([^:]+):.*/, '\1')

    begin
      klass = const_get klass_name
    rescue NameError
      klass = const_set klass_name, Class.new(self)
      klass.const_set :URN_1, "#{UPnP::DEVICE_SCHEMA_PREFIX}:#{klass.name}:1"
    end

    klass.new description.at('root > device'), url
  end

  ##
  # Searches for devices using +ssdp+ and instantiates Device objects for
  # them.  By calling this method on a subclass only devices of that type will
  # be returned.

  def self.search(ssdp = UPnP::SSDP.new)
    responses = if self == UPnP::Control::Service then
                  ssdp.search.select do |response|
                    response.type =~ /^#{UPnP::DEVICE_SCHEMA_PREFIX}/
                  end
                else
                  urns = constants.select { |name| name =~ /^URN_/ }
                  devices = urns.map { |name| const_get name }
                  ssdp.search(*devices)
                end

    responses.map { |response| create response.location }
  end

  ##
  # Creates a new Device from +device+ which can be an Nokogiri::XML::Element
  # describing the device or a URI for the device's description.  If an XML
  # description is provided, the parent device's +url+ must also be provided.

  def initialize(device, url = nil)
    @devices = []
    @sub_devices = []

    @services = []
    @sub_services = []

    case device
    when URI::Generic then
      description = Nokogiri::XML open(device)

      @url = description.at 'root > URLBase'
      @url = @url ? URI.parse(@url.text.strip) : device + '/'

      device = parse_device description.at('root > device')
    when Nokogiri::XML::Element then
      raise ArgumentError, 'url not provided with Nokogiri::XML::Element' if
        url.nil?
      @url = url
      parse_device device
    else
      raise ArgumentError, 'must be a URI or a Nokogiri::XML::Element'
    end
  end

  ##
  # Parses the Nokogiri::XML::Element +description+ and fills in various
  # attributes, sub-devices and sub-services

  def parse_device(description)
    @friendly_name = description.at('friendlyName').text.strip

    @manufacturer = description.at('manufacturer').text.strip

    manufacturer_url = description.at('manufacturerURL')
    @manufacturer_url = URI.parse manufacturer_url.text.strip if
      manufacturer_url

    model_description = description.at 'modelDescription'
    @model_description = model_description.text.strip if model_description

    @model_name = description.at('modelName').text.strip

    model_number = description.at 'modelNumber'
    @model_number = model_number.text.strip if model_number

    model_url = description.at 'modelURL'
    @model_url = URI.parse model_url.text.strip if model_url

    @name = description.at('UDN').text.strip

    presentation_url = description.at 'presentationURL'
    @presentation_url = URI.parse presentation_url.text.strip if
      presentation_url

    serial_number = description.at 'serialNumber'
    @serial_number = serial_number.text.strip if serial_number

    @type = description.at('deviceType').text.strip

    upc = description.at 'UPC'
    @upc = upc.text.strip if upc

    sub_devices = description.xpath './xmlns:deviceList/xmlns:device'
    sub_devices.each do |sub_device_description|
      sub_device = UPnP::Control::Device.new sub_device_description, @url
      @sub_devices << sub_device
    end

    @devices = @sub_devices.map do |device|
      [device, device.devices]
    end.flatten

    sub_services = description.xpath './xmlns:serviceList/xmlns:service'
    sub_services.each do |service_description|
      service = UPnP::Control::Service.create service_description, @url
      @sub_services << service
    end

    @services = (@sub_services +
                 @devices.map { |device| device.services }.flatten).uniq
  end

end

