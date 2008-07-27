require 'test/unit'
require 'test/utilities'
require 'UPnP/device'
require 'UPnP/test_utilities'

class TestUPnPDevice < UPnP::TestCase

  def setup
    super

    @device = UPnP::Device.new 'TestDevice', 'test device'
    @device.manufacturer = 'UPnP Manufacturer'
    @device.model_name = 'UPnP Model'

    @sub_device = @device.add_device 'TestDevice', 'test sub-device'
    @sub_device.manufacturer = 'UPnP Sub Manufacturer'
    @sub_device.model_name = 'UPnP Sub Model'

    @service = @device.add_service 'TestService'
  end

  def test_self_add_serivce_id
    assert_equal 'urn:example-com:serviceId:TestService',
                 @device.service_id(@service)
  end

  def test_self_create
    device1 = UPnP::Device.create 'TestDevice', 'test device'

    dump = File.join @home, '.UPnP', 'TestDevice', 'test device'

    assert File.exist?(dump)

    device2 = UPnP::Device.create 'TestDevice', 'test device'

    assert_equal device1.name, device2.name, 'UUIDs not identical'
  end

  def test_self_create_edit
    device1 = UPnP::Device.create 'TestDevice', 'test device' do |d|
      d.manufacturer = 'manufacturer 1'

      d.add_device 'TestDevice', 'embedded device' do |d2|
        d2.manufacturer = 'embedded manufacturer'
      end
    end

    device2 = UPnP::Device.create 'TestDevice', 'test device' do |d|
      d.manufacturer = 'manufacturer 2'

      d.add_device 'TestDevice', 'embedded device' do |d2|
        d2.manufacturer = 'embedded manufacturer 2'
      end
    end

    assert_equal device1.name, device2.name, 'UUIDs not identical'

    assert_equal 2, device2.devices.length, 'wrong number of devices'

    assert_equal device1.devices.last.name,
                 device2.devices.last.name, 'sub-device UUIDs not identical'

    assert_not_equal device2.name, device2.devices.last.name

    assert_equal 'manufacturer 2', device2.manufacturer, 'block not called'
    assert_equal 'embedded manufacturer 2',
                 device2.devices.last.manufacturer,
                 'sub-device block not called'

    device3 = UPnP::Device.create 'TestDevice', 'test device'

    assert_equal 'manufacturer 2', device3.manufacturer,
                 'not dumped from Marshal'
  end

  def test_initialize
    assert_kind_of UPnP::Device::TestDevice, @device
    assert_equal 'test device', @device.friendly_name
    assert_match %r%\Auuid:.{36}\Z%, @device.name
  end

  def test_add_device
    assert_equal @device, @sub_device.parent
    assert_equal 'test sub-device', @sub_device.friendly_name
    assert_equal 'TestDevice', @sub_device.type

    assert @device.sub_devices.include?(@sub_device)
  end

  def test_add_device_exists
    device = @device.add_device @sub_device.type,
                                @sub_device.friendly_name do |d|
      d.manufacturer = 'new manufacturer'
    end

    assert_equal 2, @device.devices.length, 'wrong number of devices'

    assert_equal 'new manufacturer', device.manufacturer
  end

  def test_add_service
    assert_equal @device, @service.device

    assert @device.sub_services.include?(@service)
  end

  def test_description
    desc = @device.description

    desc = desc.gsub(/uuid:.{8}-.{4}-.{4}-.{4}-.{12}/,
                     'uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX')

    expected = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:TestDevice:1</deviceType>
    <UDN>uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX</UDN>
    <friendlyName>test device</friendlyName>
    <manufacturer>UPnP Manufacturer</manufacturer>
    <modelName>UPnP Model</modelName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:TestService:1</serviceType>
        <serviceId>urn:example-com:serviceId:TestService</serviceId>
        <SCPDURL>/TestDevice/TestService</SCPDURL>
        <controlURL>/TestDevice/TestService/control</controlURL>
        <eventSubURL>/TestDevice/TestService/event_sub</eventSubURL>
      </service>
    </serviceList>
    <deviceList>
      <device>
        <deviceType>urn:schemas-upnp-org:device:TestDevice:1</deviceType>
        <UDN>uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX</UDN>
        <friendlyName>test sub-device</friendlyName>
        <manufacturer>UPnP Sub Manufacturer</manufacturer>
        <modelName>UPnP Sub Model</modelName>
      </device>
    </deviceList>
  </device>
</root>
    XML

    assert_equal expected, desc
  end

  def test_device_description
    desc = ''
    xml = Builder::XmlMarkup.new :indent => 2, :target => desc

    @sub_device.device_description xml

    desc = desc.gsub(/uuid:.{8}-.{4}-.{4}-.{4}-.{12}/,
                     'uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX')

    expected = <<-XML
<device>
  <deviceType>urn:schemas-upnp-org:device:TestDevice:1</deviceType>
  <UDN>uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX</UDN>
  <friendlyName>test sub-device</friendlyName>
  <manufacturer>UPnP Sub Manufacturer</manufacturer>
  <modelName>UPnP Sub Model</modelName>
</device>
    XML

    assert_equal expected, desc
  end

  def test_devices
    assert_equal ['test device', 'test sub-device'],
                 @device.devices.map { |d| d.friendly_name }, 'device'
    assert_equal ['test sub-device'],
                 @sub_device.devices.map { |d| d.friendly_name }, 'sub-device'
  end

  def test_dump
    @device.dump

    dump_file = File.join @home, '.UPnP', @device.type, @device.friendly_name

    assert File.exist?(dump_file)

    marshal_version = IO.read dump_file, 2

    major, minor = marshal_version.unpack 'CC'

    assert_equal Marshal::MAJOR_VERSION, major
    assert_equal Marshal::MINOR_VERSION, minor
  end

  def test_marshal_dump
    dump = @device.marshal_dump
    assert_equal 'TestDevice',        dump.shift, 'type'
    assert_equal 'test device',       dump.shift, 'friendly name'
    assert_equal [@sub_device],       dump.shift, 'sub-devices'
    assert_equal [@service],          dump.shift, 'sub-services'
    assert_equal nil,                 dump.shift, 'parent'
    assert_match %r%uuid:.{36}%,      dump.shift, 'name'
    assert_equal 'UPnP Manufacturer', dump.shift, 'manufacturer'
    assert_equal nil,                 dump.shift, 'manufacturer url'
    assert_equal nil,                 dump.shift, 'model description'
    assert_equal 'UPnP Model',        dump.shift, 'model name'
    assert_equal nil,                 dump.shift, 'model number'
    assert_equal nil,                 dump.shift, 'model url'
    assert_equal nil,                 dump.shift, 'serial number'
    assert_equal nil,                 dump.shift, 'upc'

    assert dump.empty?, 'device not empty'
  end

  def test_marshal_load
    data = (1..14).to_a

    @device.marshal_load data

    assert_equal 1,  @device.type
    assert_equal 2,  @device.friendly_name
    assert_equal 3,  @device.sub_devices
    assert_equal 4,  @device.sub_services
    assert_equal 5,  @device.parent
    assert_equal 6,  @device.name
    assert_equal 7,  @device.manufacturer
    assert_equal 8,  @device.manufacturer_url
    assert_equal 9,  @device.model_description
    assert_equal 10, @device.model_name
    assert_equal 11, @device.model_number
    assert_equal 12, @device.model_url
    assert_equal 13, @device.serial_number
    assert_equal 14, @device.upc

    assert data.empty?, 'data not consumed'
  end

  def test_root_device
    assert_equal @device, @device.root_device
    assert_equal @device, @sub_device.root_device
  end

  def test_service_id
    assert_equal 'urn:example-com:serviceId:TestService',
                 @device.service_id(@service)
  end

  def test_service_ids
    expected = {
      UPnP::Service::TestService => 'urn:example-com:serviceId:TestService'
    }

    assert_equal expected, @device.service_ids
  end

  def test_services
    assert_equal [@service], @device.services
    assert_equal [], @sub_device.services
  end

  def test_setup_server
    server = @device.setup_server

    mount_tab = server.instance_variable_get :@mount_tab

    assert mount_tab[@service.scpd_url]
  end

  def test_type_urn
    assert_equal "#{UPnP::DEVICE_SCHEMA_PREFIX}:TestDevice:1",
                 @device.type_urn
  end

  def test_validate
    @device.friendly_name = nil

    e = assert_raise UPnP::Device::ValidationError do
      @device.validate
    end

    assert_equal 'friendly_name missing', e.message

    @device.friendly_name = 'name'

    @device.manufacturer = nil

    e = assert_raise UPnP::Device::ValidationError do
      @device.validate
    end

    assert_equal 'manufacturer missing', e.message

    @device.manufacturer = 'manufacturer'

    @device.model_name = nil

    e = assert_raise UPnP::Device::ValidationError do
      @device.validate
    end

    assert_equal 'model_name missing', e.message
  end

end

