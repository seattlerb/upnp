require 'test/unit'
require 'test/utilities'
require 'UPnP/SSDP'

class TestUPnPSSDP < UPnP::TestCase

  def setup
    @ssdp = UPnP::SSDP.new
    @ssdp.timeout = 0
  end

  def teardown
    @ssdp.listener.kill if @ssdp.listener
  end

  def test_discover
    socket = UPnP::FakeSocket.new util_notify
    @ssdp.socket = socket

    notifications = @ssdp.discover

    assert_equal [], socket.sent
    assert_equal [Socket::INADDR_ANY, @ssdp.port], socket.bound

    expected = [
      [Socket::IPPROTO_IP, Socket::IP_TTL, [@ssdp.ttl].pack('i')],
      [Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP,
       "\357\377\377\372\000\000\000\000"]
    ]

    assert_equal expected, socket.socket_options

    assert_equal 1, notifications.length
    assert_equal 'upnp:rootdevice', notifications.first.type
  end

  def test_listen
    @ssdp.socket = UPnP::FakeSocket.new util_notify

    @ssdp.listen

    notification = @ssdp.queue.pop

    assert_equal 'upnp:rootdevice', notification.type
  end

  def test_parse_bad
    assert_raise UPnP::SSDP::Error do
      @ssdp.parse ''
    end
  end

  def test_parse_notification
    notification = @ssdp.parse util_notify

    assert_equal 'upnp:rootdevice', notification.type
  end

  def test_parse_notification_byebye
    notification = @ssdp.parse util_notify

    assert_equal 'upnp:rootdevice', notification.type
  end

  def test_parse_search_response
    response = @ssdp.parse util_search_response

    assert_equal 'upnp:rootdevice', response.target
  end

  def test_search
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search

    assert_equal nil, socket.bound

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: ssdp:all\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent

    expected = [
      [Socket::IPPROTO_IP, Socket::IP_TTL, [@ssdp.ttl].pack('i')],
    ]

    assert_equal expected, socket.socket_options

    assert_equal 1, responses.length
    assert_equal 'upnp:rootdevice', responses.first.target
  end

  def test_search_device
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search [:device, 'MyDevice.1']

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: urn:schemas-upnp-org:device:MyDevice.1\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_search_root
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search :root

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: upnp:rootdevice\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_search_service
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search [:service, 'MyService.1']

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: urn:schemas-upnp-org:service:MyService.1\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_search_ssdp
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search 'ssdp:foo'

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: ssdp:foo\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_search_urn
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search 'urn:foo'

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: urn:foo\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_search_uuid
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search 'uuid:foo'

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: uuid:foo\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_send_search
    socket = UPnP::FakeSocket.new
    @ssdp.socket = socket

    @ssdp.send_search 'bunnies'

    search = <<-SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: bunnies\r
\r
    SEARCH

    assert_equal [[search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_stop_listening
    thread = Thread.new do sleep end
    @ssdp.listener = thread

    @ssdp.stop_listening

    assert_equal false, thread.alive?
    assert_equal nil, @ssdp.listener
  end

end

