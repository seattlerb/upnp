require 'test/unit'
require 'test/utilities'
require 'UPnP/SSDP'
require 'UPnP/device'

class TestUPnPSSDP < UPnP::TestCase

  def setup
    super

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

    assert_equal 1, notifications.length
    assert_equal 'upnp:rootdevice', notifications.first.type
  end

  def test_listen
    @ssdp.socket = UPnP::FakeSocket.new util_notify

    @ssdp.listen

    notification = @ssdp.queue.pop

    assert_equal 'upnp:rootdevice', notification.type
  end

  def test_new_socket
    UPnP::SSDP.send :const_set, :UDPSocket, UPnP::FakeSocket

    socket = @ssdp.new_socket

    ttl = [@ssdp.ttl].pack 'i'
    expected = [
      [Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, "\357\377\377\372\000\000\000\000"],
      [Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, "\000"],
      [Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, ttl],
      [Socket::IPPROTO_IP, Socket::IP_TTL, ttl],
    ]

    assert_equal expected, socket.socket_options
  ensure
    UPnP::SSDP.send :remove_const, :UDPSocket
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

  def test_parse_search
    response = @ssdp.parse util_search

    assert_equal 'upnp:rootdevice', response.target
  end

  def test_parse_search_response
    response = @ssdp.parse util_search_response

    assert_equal 'upnp:rootdevice', response.target
  end

  def test_search
    socket = UPnP::FakeSocket.new util_search_response
    @ssdp.socket = socket

    responses = @ssdp.search

    m_search = <<-M_SEARCH
M-SEARCH * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
MAN: \"ssdp:discover\"\r
MX: 0\r
ST: ssdp:all\r
\r
    M_SEARCH

    assert_equal [[m_search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent

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

  def test_send_notify
    socket = UPnP::FakeSocket.new
    @ssdp.socket = socket

    uri = 'http://127.255.255.255:65536/description'
    device = UPnP::Device.new 'TestDevice', 'test device'

    @ssdp.send_notify uri, 'upnp:rootdevice', device

    search = <<-SEARCH
NOTIFY * HTTP/1.1\r
HOST: 239.255.255.250:1900\r
CACHE-CONTROL: max-age=120\r
LOCATION: #{uri}\r
NT: upnp:rootdevice\r
NTS: ssdp:alive\r
SERVER: Ruby UPnP/#{UPnP::VERSION} UPnP/1.0 UPnP::Device::TestDevice/1.0.0\r
USN: #{device.name}::upnp:rootdevice\r
\r
    SEARCH

    assert_equal [[search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
  end

  def test_send_response
    socket = UPnP::FakeSocket.new
    @ssdp.socket = socket

    uri = 'http://127.255.255.255:65536/description'
    device = UPnP::Device.new 'TestDevice', 'test device'

    @ssdp.send_response uri, 'upnp:rootdevice', device.name, device

    search = <<-SEARCH
HTTP/1.1 200 OK\r
CACHE-CONTROL: max-age=120\r
EXT:\r
LOCATION: #{uri}\r
SERVER: Ruby UPnP/#{UPnP::VERSION} UPnP/1.0 UPnP::Device::TestDevice/1.0.0\r
ST: upnp:rootdevice\r
NTS: ssdp:alive\r
USN: #{device.name}\r
Content-Length: 0\r
\r
    SEARCH

    assert_equal [[search, 0, @ssdp.broadcast, @ssdp.port]], socket.sent
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

