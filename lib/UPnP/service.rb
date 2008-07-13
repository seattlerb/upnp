require 'UPnP'
require 'soap/rpc/standaloneServer'

##
# A service contains a SOAP endpoint and the Service Control Protocol
# Definition (SCPD).  It acts as a SOAP server that is mounted onto the
# RootServer along with the containing devices and other devices and services
# in a UPnP device.
#
# = Creating a UPnP::Service class
#
# A concrete UPnP service looks like this:
#
#   require 'UPnP/service'
#   
#   class UPnP::Service::ContentDirectory < UPnP::Service
#   
#     add_action 'Browse',
#       [IN, 'ObjectID',       'A_ARG_TYPE_ObjectID'],
#       # ...
#   
#       [OUT, 'Result',         'A_ARG_TYPE_Result'],
#       # ...
#   
#     add_variable 'A_ARG_TYPE_ObjectID', 'string'
#     add_variable 'A_ARG_TYPE_Result',   'string'
#   end
#
# Subclass UPnP::Service in the UPnP::Service namespace.  UPnP::Service looks
# in its own namespace for various information when instantiating the service.
#
# #add_action defines a service's action.  The action's arguments follow the
# name as arrays of direction (IN, OUT, RETVAL), argument name, and related
# state variable.
#
# #add_variable defines a state table variable.  The name is followed by the
# type, allowed values, default value and whether or not the variable is
# evented.
#
# = Instantiating  a UPnP::Service
#
# A UPnP::Service will be instantiated automatically for you if you call
# add_service in the UPnP::Device initialization block.  If you want to
# instantiate a service by hand, use ::create to pick the correct subclass
# automatically.

class UPnP::Service < SOAP::RPC::StandaloneServer

  ##
  # Base service error class

  class Error < UPnP::Error
  end

  ##
  # Maps actions for a service to their arguments

  ACTIONS = Hash.new { |h, service| h[service] = {} }

  ##
  # Maps state variables for a service to their variable information

  VARIABLES = Hash.new { |h, service| h[service] = {} }

  ##
  # SOAP input argument type

  IN = SOAP::RPC::SOAPMethod::IN

  ##
  # SOAP output argument type

  OUT = SOAP::RPC::SOAPMethod::OUT

  ##
  # SOAP return value argument type

  RETVAL = SOAP::RPC::SOAPMethod::RETVAL

  ##
  # UPnP 1.0 service schema

  SCHEMA_URN = 'urn:schemas-upnp-org:service-1-0'

  ##
  # This service's parent

  attr_reader :device

  ##
  # Type of UPnP service.  Use type_urn for the full URN

  attr_reader :type

  ##
  # Adds the action +name+ to this class with +arguments+

  def self.add_action(name, *arguments)
    ACTIONS[self][name] = arguments
  end

  ##
  # Adds a state variable +name+ to this class

  def self.add_variable(name, type, allowed_values = nil, default = nil,
                        evented = false)
    VARIABLES[self][name] = [type, allowed_values, default, evented]
  end

  ##
  # Creates a new service under +device+ of the given +type+.  Requires a
  # concrete subclass of UPnP::Service.

  def self.create(device, type)
    klass = const_get type
    klass.new device, type
  rescue NameError => e
    raise unless e.message =~ /UPnP::Service::#{type}/
    raise Error, "unknown service type #{type}"
  end

  ##
  # Creates a new service under +device+ of the given +type+

  def initialize(device, type)
    @device = device
    @type = type

    super @type, type_urn

    add_actions
  end

  ##
  # Actions for this service

  def actions
    ACTIONS[self.class]
  end

  ##
  # Adds RPC actions to this service

  def add_actions
    actions.each do |name, params|
      add_rpc_method self, name, params
    end
  end

  ##
  # The control URL for this service

  def control_url
    File.join device_path, @type, 'control'
  end

  ##
  # Tell the StandaloneServer to not listen, RootServer does this for us

  def create_config
    hash = super
    hash[:DoNotListen] = true
    hash
  end

  ##
  # Adds a description of this service to XML::Builder +xml+

  def description(xml)
    xml.service do
      xml.serviceType type_urn
      xml.serviceId   "urn:upnp-org:serviceId:#{root_device.service_id self}"
      xml.SCPDURL     scpd_url
      xml.controlURL  control_url
      xml.eventSubURL event_sub_url
    end
  end

  ##
  # The path for this service's parent device

  def device_path
    devices = []
    device = @device

    until device.nil? do
      devices << device
      device = device.parent
    end

    File.join('/', *devices.map { |d| d.type })
  end

  ##
  # The event subscription url for this service

  def event_sub_url
    File.join device_path, @type, 'event_sub'
  end

  ##
  # Dumps only information necessary to run initialize.  Server state is not
  # persisted.

  def marshal_dump
    [
      @device,
      @type
    ]
  end

  ##
  # Loads data and initializes the server.

  def marshal_load(data)
    device = data.shift
    type   = data.shift

    initialize device, type

    add_actions
  end

  ##
  # The root device for this service

  def root_device
    @device.root_device
  end

  ##
  # The SCPD for this service

  def scpd
    xml = Builder::XmlMarkup.new :indent => 2
    xml.instruct!

    xml.scpd :xmlns => SCHEMA_URN do
      xml.specVersion do
        xml.major 1
        xml.minor 0
      end

      scpd_action_list xml

      scpd_service_state_table xml
    end
  end

  ##
  # Adds the SCPD actionList to XML::Builder +xml+.

  def scpd_action_list(xml)
    xml.actionList do
      actions.sort_by { |name,| name }.each do |name, arguments|
        xml.action do
          xml.name name
          xml.argumentList do
            arguments.each do |arg_name, direction, state_variable|
              xml.argument do
                xml.name arg_name
                xml.direction direction
                xml.relatedStateVariable state_variable
              end
            end
          end
        end
      end
    end
  end

  ##
  # Adds the SCPD serviceStateTable to XML::Builder +xml+.

  def scpd_service_state_table(xml)
    xml.serviceStateTable do
      variables.each do |name, (type, allowed_values, default, send_events)|
        send_events = send_events ? 'yes' : 'no'
        xml.stateVariable :sendEvents => send_events do
          xml.name name
          xml.dataType type
          if allowed_values then
            xml.allowedValueList do
              allowed_values.each do |value|
                xml.allowedValue value
              end
            end
          end
        end
      end
    end
  end

  ##
  # The SCPD url for this service

  def scpd_url
    File.join device_path, @type
  end

  ##
  # URN of this service's type

  def type_urn
    "#{UPnP::SERVICE_SCHEMA_PREFIX}:#{@type}:1"
  end

  ##
  # Returns a Hash of state variables for this service

  def variables
    VARIABLES[self.class]
  end

end

