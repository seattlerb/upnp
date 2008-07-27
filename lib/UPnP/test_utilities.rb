require 'UPnP/device'
require 'UPnP/service'

class UPnP::Service::TestService < UPnP::Service
  VERSION = '1.0'
end

class UPnP::Device::TestDevice < UPnP::Device
  VERSION = '1.0'

  add_service_id UPnP::Service::TestService, 'TestService', 'example.com'
end

