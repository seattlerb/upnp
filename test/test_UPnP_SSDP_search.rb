require 'test/unit'
require 'test/utilities'
require 'UPnP/SSDP'

class TestUPnPSSDPSearch < UPnP::TestCase

  def test_self_parse_search
    search = UPnP::SSDP::Search.parse util_search

    assert_equal Time, search.date.class
    assert_equal 'upnp:rootdevice', search.target
    assert_equal 2, search.wait_time
  end

  def test_inspect
    search = UPnP::SSDP::Search.parse util_search

    id = search.object_id.to_s 16
    expected = "#<UPnP::SSDP::Search:0x#{id} upnp:rootdevice>"

    assert_equal expected, search.inspect
  end

end

