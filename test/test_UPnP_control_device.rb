require 'test/unit'
require 'stringio'
require 'test/utilities'
require 'UPnP/control/device'

class TestUPnPControlDevice < UPnP::TestCase

  def setup
    @device_url = URI.parse 'http://example.com/device.xml'

    UPnP::OpenStub::FILES[@device_url] = StringIO.new UPnP::TestCase::IGD_XML
    UPnP::OpenStub::FILES[@device_url + '/L3F.xml'] =
      StringIO.new UPnP::TestCase::L3F_XML
    UPnP::OpenStub::FILES[@device_url + '/WANCfg.xml'] =
      StringIO.new UPnP::TestCase::CFG_XML
    UPnP::OpenStub::FILES[@device_url + '/WANIPCn.xml'] =
      StringIO.new UPnP::TestCase::IPCN_XML
  end

  def test_self_create
    device = UPnP::Control::Device.create @device_url

    assert_equal UPnP::Control::Device::InternetGatewayDevice, device.class
  ensure
    UPnP::Control::Device.send :remove_const, :InternetGatewayDevice
  end

  def test_self_create_class_exists
    UPnP::Control::Device.const_set :InternetGatewayDevice,
                                    Class.new(UPnP::Control::Device)

    device = UPnP::Control::Device.create @device_url

    assert_equal UPnP::Control::Device::InternetGatewayDevice, device.class
  ensure
    UPnP::Control::Device.send :remove_const, :InternetGatewayDevice
  end

  def test_initialize
    device = UPnP::Control::Device.new @device_url

    assert_equal 'http://example.com/', device.url.to_s
    assert_equal 'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
                 device.type

    assert_equal 'FreeBSD router', device.friendly_name

    assert_equal 'FreeBSD', device.manufacturer
    assert_equal URI.parse('http://www.freebsd.org/'), device.manufacturer_url

    assert_equal 'FreeBSD router', device.model_description
    assert_equal 'FreeBSD router', device.model_name
    assert_equal URI.parse('http://www.freebsd.org/'), device.model_url
    assert_equal '1', device.model_number

    assert_equal '00000000', device.serial_number

    assert_equal 'uuid:ed56cff8-7d4e-11dc-b7db-000024c4931c', device.name

    assert_equal 2, device.devices.length, 'devices count'
    assert_equal 1, device.sub_devices.length, 'sub-devices count'

    assert_equal 3, device.services.length, 'services count'
    assert_equal 1, device.sub_services.length, 'sub-services count'
  end

end

