$KCODE = 'u'

require 'rubygems'
gem 'soap4r'

##
# An implementation of the Universal Plug and Play protocol.
#
# http://upnp.org/

module UPnP

  ##
  # UPnP device schema prefix

  DEVICE_SCHEMA_PREFIX = 'urn:schemas-upnp-org:device'

  ##
  # UPnP service schema prefix

  SERVICE_SCHEMA_PREFIX = 'urn:schemas-upnp-org:service'

  ##
  # The version of UPnP you are using

  VERSION = '1.3.0'

  ##
  # UPnP error base class

  class Error < RuntimeError
  end

end

