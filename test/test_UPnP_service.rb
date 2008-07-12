require 'test/unit'
require 'test/utilities'
require 'UPnP/service'

class TestUPnPService < UPnP::TestCase

  def setup
    super

    @device = UPnP::Device.new 'TestDevice', 'test device'
    @service = @device.add_service 'TestService'
  end

  def test_initialize
    assert_equal @device, @service.device
    assert_equal 'TestService', @service.type

    assert_equal 'TestService', @service.appname
    assert_equal "#{UPnP::SERVICE_SCHEMA_PREFIX}:TestService:1",
                 @service.default_namespace

    router = @service.instance_variable_get :@router
    operations = router.instance_variable_get :@operation_by_qname

    qname = XSD::QName.new @service.type_urn, 'TestAction'

    assert operations.key?(qname)
  end

  def test_actions
    expected = {
      'TestAction' => [
        %w[in  TestInput  TestInVar],
        %w[out TestOutput TestOutVar],
      ],
    }

    assert_equal expected, @service.actions
  end

  def test_add_actions
    router = @service.instance_variable_get :@router
    operations = router.instance_variable_get :@operation_by_qname

    qname = XSD::QName.new @service.type_urn, 'TestAction'

    assert_equal [qname], operations.keys
  end

  def test_control_url
    assert_equal '/TestDevice/TestService/control', @service.control_url
  end

  def test_create_config
    assert_equal true, @service.create_config[:DoNotListen]
  end

  def test_description
    desc = ''
    xml = Builder::XmlMarkup.new :indent => 2, :target => desc

    @service.description xml

    expected = <<-XML
<service>
  <serviceType>urn:schemas-upnp-org:service:TestService:1</serviceType>
  <serviceId>urn:upnp-org:serviceId:TestService</serviceId>
  <SCPDURL>/TestDevice/TestService</SCPDURL>
  <controlURL>/TestDevice/TestService/control</controlURL>
  <eventSubURL>/TestDevice/TestService/event_sub</eventSubURL>
</service>
    XML

    assert_equal expected, desc
  end

  def test_device_path
    assert_equal '/TestDevice', @service.device_path
  end

  def test_event_sub_url
    assert_equal '/TestDevice/TestService/event_sub', @service.event_sub_url
  end

  def test_marshal_dump
    assert_equal [@device, 'TestService'], @service.marshal_dump
  end

  def test_marshal_load
    data = [@device, 'TestService']

    service = UPnP::Service.allocate

    service.marshal_load data

    assert_equal 'TestService', @service.type
    assert_equal 'TestService', @service.appname

    assert data.empty?, 'unconsumed data'
  end

  def test_root_device
    assert_equal @device, @service.root_device
  end

  def test_scpd
    scpd = @service.scpd

    expected = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <actionList>
    <action>
      <name>TestAction</name>
      <argumentList>
        <argument>
          <name>in</name>
          <direction>TestInput</direction>
          <relatedStateVariable>TestInVar</relatedStateVariable>
        </argument>
        <argument>
          <name>out</name>
          <direction>TestOutput</direction>
          <relatedStateVariable>TestOutVar</relatedStateVariable>
        </argument>
      </argumentList>
    </action>
  </actionList>
  <serviceStateTable>
    <stateVariable sendEvents="no">
      <name>TestOutVar</name>
      <dataType>string</dataType>
    </stateVariable>
    <stateVariable sendEvents="no">
      <name>TestInVar</name>
      <dataType>string</dataType>
    </stateVariable>
  </serviceStateTable>
</scpd>
    XML

    assert_equal expected, scpd
  end

  def test_scpd_url
    assert_equal '/TestDevice/TestService', @service.scpd_url
  end

  def test_type_urn
    assert_equal 'urn:schemas-upnp-org:service:TestService:1', @service.type_urn
  end

  def test_variables
    expected = {
      'TestOutVar' => ['string', nil, nil, false],
      'TestInVar'  => ['string', nil, nil, false],
    }

    assert_equal expected, @service.variables
  end

end

