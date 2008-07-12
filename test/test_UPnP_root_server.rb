require 'stringio'
require 'test/unit'
require 'test/utilities'
require 'UPnP/root_server'

class TestUPnPRootServer < UPnP::TestCase

  def setup
    super

    @device = UPnP::Device.new 'TestDevice', 'test device'
    @device.manufacturer = 'UPnP Manufacturer'
    @device.model_name = 'UPnP Model'

    @service = @device.add_service 'TestService'

    @root_server = UPnP::RootServer.new @device

    @req = WEBrick::HTTPRequest.new :Logger => nil
    @res = WEBrick::HTTPResponse.new :HTTPVersion => '1.0'
  end

  def test_initialize
    assert_equal @device, @root_server.root_device
    assert @root_server.scpds.empty?
    assert_equal WEBrick::BasicLog::FATAL, @root_server.logger.level

    assert util_mount_tab['/description']
  end

  def test_description
    data = StringIO.new "GET /description HTTP/1.0\r\n\r\n"
    @req.parse data

    @root_server.description @req, @res

    assert_equal 200, @res.status, @res.body
    assert_equal 'text/xml', @res['content-type']
    assert_equal @device.description, @res.body
  end

  def test_description_other
    data = StringIO.new "GET /description/other HTTP/1.0\r\n\r\n"
    @req.parse data

    assert_raise WEBrick::HTTPStatus::NotFound do
      @root_server.description @req, @res
    end
  end

  def test_mount_server
    assert_nil util_mount_tab['/TestDevice/TestService/control']

    @root_server.mount_server @service.control_url, @service.server

    assert_equal @root_server.logger, @service.server.config[:Logger]
    assert util_mount_tab['/TestDevice/TestService/control']
  end

  def test_mount_service
    @root_server.mount_service @service

    assert_equal [@service.scpd_url], @root_server.scpds.keys

    assert util_mount_tab['/TestDevice/TestService']
    assert util_mount_tab['/TestDevice/TestService/control']
  end

  def test_scpd
    @root_server.mount_service @service

    data = StringIO.new "GET #{@service.scpd_url} HTTP/1.0\r\n\r\n"
    @req.parse data

    @root_server.scpd @req, @res

    assert_equal 200, @res.status, @res.body
    assert_equal 'text/xml', @res['content-type']
    assert_equal @service.scpd, @res.body
  end

  def test_scpd_other
    @root_server.mount_service @service

    data = StringIO.new "GET /TestDevice/TestOtherService HTTP/1.0\r\n\r\n"
    @req.parse data

    assert_raise WEBrick::HTTPStatus::NotFound do
      @root_server.description @req, @res
    end
  end

  def util_mount_tab
    @root_server.instance_variable_get :@mount_tab
  end

end

