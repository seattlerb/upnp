require 'test/unit'
require 'test/utilities'
require 'UPnP/control/service'

class TestUPnPControlService < UPnP::TestCase

  def setup
    super

    @url = URI.parse 'http://example.com'
    service_description = <<-XML
<service>
  <serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType>
  <serviceId>urn:upnp-org:serviceId:Layer3Forwarding1</serviceId>
  <controlURL>/ctl/L3F</controlURL>
  <eventSubURL>/evt/L3F</eventSubURL>
  <SCPDURL>/L3F.xml</SCPDURL>
</service>
    XML

    service_description = REXML::Document.new service_description
    @service_description = service_description.elements['service']

    UPnP::Control::Service::FILES[@url + '/L3F.xml'] = StringIO.new L3F_XML

    @methods = %w[
      AddPortMapping
      DeletePortMapping
      ForceTermination
      GetConnectionTypeInfo
      GetExternalIPAddress
      GetGenericPortMappingEntry
      GetNATRSIPStatus
      GetSpecificPortMappingEntry
      GetStatusInfo
      RequestConnection
      SetConnectionType
    ]
  end

  def test_self_create
    device = UPnP::Control::Service.create @service_description, @url

    l3f = UPnP::Control::Service::Layer3Forwarding
    assert_equal l3f, device.class

    assert l3f.constants.include?('URN_1'), 'URN_1 constant missing'
    assert_equal "#{UPnP::SERVICE_SCHEMA_PREFIX}:#{l3f.name}:1", l3f::URN_1
  ensure
    UPnP::Control::Service.send :remove_const, :Layer3Forwarding
  end

  def test_self_create_class_exists
    UPnP::Control::Service.const_set :Layer3Forwarding,
                                    Class.new(UPnP::Control::Service)

    device = UPnP::Control::Service.create @service_description, @url

    assert_equal UPnP::Control::Service::Layer3Forwarding, device.class
  ensure
    UPnP::Control::Service.send :remove_const, :Layer3Forwarding
  end

  def test_initialize
    service = UPnP::Control::Service.new @service_description, @url

    assert_equal @url, service.url

    assert_equal 'urn:schemas-upnp-org:service:Layer3Forwarding:1',
                 service.type

    assert_equal 'urn:upnp-org:serviceId:Layer3Forwarding1', service.id

    control_url = @url + '/ctl/L3F'
    assert_equal control_url, service.control_url

    evt_url = @url + '/evt/L3F'
    assert_equal evt_url, service.event_sub_url

    scpd_url = @url + '/L3F.xml'
    assert_equal scpd_url, service.scpd_url

    assert_not_nil service.driver
  end

  def test_create_driver
    service = UPnP::Control::Service.create @service_description, @url

    assert_equal @methods, service.driver.methods(false).sort

    registry = service.driver.mapping_registry

    klass_def = registry.elename_schema_definition_from_class SOAP::SOAPString
    assert_equal 'NewPossibleConnectionTypes', klass_def.elename.name

    new_protocol = XSD::QName.new nil, 'NewProtocol'
    mapping = registry.schema_definition_from_elename new_protocol
    assert mapping, "Mapping for #{new_protocol} not found"

    assert service.respond_to?(@methods.first)
  end

  def test_methods
    service = UPnP::Control::Service.new @service_description, @url

    assert_equal @methods, service.methods(false).sort
  end

end

