require 'UPnP/control'

require 'date'
require 'open-uri'
require 'rexml/document'
require 'soap/rpc/driver'
require 'time'
require 'uri'

##
# A service on a UPnP control point.
#
# A Service exposes the UPnP actions as ordinary ruby methods, which are
# handled via method_missing.  A Service responds appropriately to respond_to?
# and methods to make introspection easy.
#
# Services should be created using ::create instead of ::new.  This allows a
# subclass of Service to be automatically instantiated.
#
# When creating a service subclass, it must have a URN_version constant set to
# the schema URN for that version.
#
# For details on UPnP services, see http://www.upnp.org/resources/documents.asp

class UPnP::Control::Service

  ##
  # Service error class

  class Error < UPnP::Error
  end

  ##
  # Error raised when there was an error while calling an action

  class UPnPError < Error

    ##
    # The UPnP fault code

    attr_accessor :code

    ##
    # The UPnP fault description

    attr_accessor :description

    ##
    # Creates a new UPnP error using +description+ and +code+

    def initialize(description, code)
      @code = code
      @description = description
    end

    ##
    # Error string including code and description

    def to_s
      "#{@description} (#{@code})"
    end

  end

  ##
  # UPnP relies on the client to do type conversions.  This registry casts the
  # SOAPString returned by the service into the real SOAP type so soap4r can
  # make the conversion.

  class Registry < SOAP::Mapping::EncodedRegistry

    ##
    # If +node+ is a simple type, cast it to the real type from the registered
    # definition and super, otherwise just let EncodedRegistry do the work.

    def soap2obj(node, klass = nil)
      case node
      when XSD::XSDAnySimpleType then
        definition = find_node_definition node

        return super if definition.nil?

        new_class = definition.class_for
        new_node = new_class.new node.data

        return super(new_node, klass)
      when SOAP::SOAPStruct then
        return '' if node.members.empty?
      end

      super
    end

  end

  ##
  # Namespace for UPnP type extensions

  module Types

    ##
    # A one-byte string

    class Char < SOAP::SOAPString

      ##
      # Ensures the string is only one character long.

      def screen_data(value)
        super

        if value.sub(/./mu, '').length > 1 then
          raise ValueSpaceError, "#{type}: cannot accept '#{value}'."
        end

        value
      end

    end

    ##
    # A Universally Unique Identifier

    class UUID < SOAP::SOAPString

      def screen_data(data)
        super

        unless value.gsub('-', '') =~ /\A[a-f\d]{32}\z/ then
          raise ValueSpaceError, "#{type}: cannot accept '#{value}'."
        end

        value
      end

    end

    ##
    # Map UPnP data types to SOAP data types

    MAP = {
      'ui1'         => SOAP::SOAPUnsignedByte,
      'ui2'         => SOAP::SOAPUnsignedShort,
      'ui4'         => SOAP::SOAPUnsignedInt,

      'i1'          => SOAP::SOAPByte,
      'i2'          => SOAP::SOAPShort,
      'i4'          => SOAP::SOAPInt,
      'int'         => SOAP::SOAPInt,

      'r4'          => SOAP::SOAPFloat,
      'r8'          => SOAP::SOAPDouble,
      'number'      => SOAP::SOAPDouble,
      'float'       => SOAP::SOAPDecimal,
      'fixed.14.4'  => SOAP::SOAPDouble, # HACK not accurate

      'char'        => Char,
      'string'      => SOAP::SOAPString,

      'date'        => SOAP::SOAPDate,
      'dateTime'    => SOAP::SOAPDateTime,
      'dateTime.tz' => SOAP::SOAPDateTime,
      'time'        => SOAP::SOAPTime,
      'time.tz'     => SOAP::SOAPTime,

      'boolean'     => SOAP::SOAPBoolean,

      'bin.base64'  => SOAP::SOAPBase64,
      'bin.hex'     => SOAP::SOAPHexBinary,

      'uri'         => SOAP::SOAPAnyURI,

      'uuid'        => UUID,
    }

  end

  ##
  # Control URL

  attr_reader :control_url

  ##
  # SOAP driver for this service

  attr_reader :driver

  ##
  # Eventing URL

  attr_reader :event_sub_url

  ##
  # Service identifier, unique within this service's devices

  attr_reader :id

  ##
  # Service description URL

  attr_reader :scpd_url

  ##
  # UPnP service type

  attr_reader :type

  ##
  # Base URL for this service's device

  attr_reader :url

  ##
  # If a concrete class exists for +description+ it is used to instantiate the
  # service, otherwise a concrete class is created subclassing Service and
  # used.

  def self.create(description, url)
    type = description.elements['serviceType'].text.strip

    # HACK need vendor namespaces
    klass_name = type.sub(/urn:[^:]+:service:([^:]+):.*/, '\1')

    begin
      klass = const_get klass_name
    rescue NameError
      klass = const_set klass_name, Class.new(self)
      klass.const_set :URN_1, "#{UPnP::SERVICE_SCHEMA_PREFIX}:#{klass.name}:1"
    end

    klass.new description, url
  end

  ##
  # Creates a new service from REXML::Element +description+ and +url+.  The
  # description must be a service fragment from a device description.

  def initialize(description, url)
    @url = url

    @type = description.elements['serviceType'].text.strip
    @id = description.elements['serviceId'].text.strip
    @control_url = @url + description.elements['controlURL'].text.strip
    @event_sub_url = @url + description.elements['eventSubURL'].text.strip
    @scpd_url = @url + description.elements['SCPDURL'].text.strip

    create_driver
  end

  ##
  # Creates the SOAP driver from description at scpd_url

  def create_driver
    parse_service_description

    @driver = SOAP::RPC::Driver.new @control_url, @type

    mapping_registry = Registry.new

    @actions.each do |name, arguments|
      soapaction = "#{@type}##{name}"
      qname = XSD::QName.new @type, soapaction

      # TODO map ranges, enumerations
      arguments = arguments.map do |direction, arg_name, variable|
        type, = @variables[variable]

        schema_name = XSD::QName.new nil, arg_name

        mapping_registry.register :class => type, :schema_name => schema_name

        [direction, arg_name, @variables[variable].first]
      end

      @driver.proxy.add_rpc_method qname, soapaction, name, arguments
      @driver.send :add_rpc_method_interface, name, arguments
    end

    @driver.mapping_registry = mapping_registry

    @actions = nil
    @variables = nil
  end

  ##
  # Handles this service's actions

  def method_missing(message, *arguments)
    return super unless respond_to? message

    begin
      @driver.send(message, *arguments)
    rescue SOAP::FaultError => e
      backtrace = caller 0

      fault_code = e.faultcode.data
      fault_string = e.faultstring.data

      detail = e.detail[fault_string]
      code = detail['errorCode'].to_i
      description = detail['errorDescription']

      backtrace.first.gsub!(/:(\d+):in `([^']+)'/) do
        line = $1.to_i - 2
        ":#{line}:in `#{message}' (method_missing)"
      end

      e = UPnPError.new description, code
      e.set_backtrace backtrace
      raise e
    end
  end

  ##
  # Includes this service's actions

  def methods(include_ancestors = true)
    super + @driver.methods(false)
  end

  ##
  # Extracts arguments for an action from +argument_list+

  def parse_action_arguments(argument_list)
    arguments = []

    argument_list.each_element 'argument' do |argument|
      name = argument.elements['name'].text.strip

      direction = argument.elements['direction'].text.strip.upcase
      direction = 'RETVAL' if argument.elements['retval']
      direction = SOAP::RPC::SOAPMethod.const_get direction
      variable  = argument.elements['relatedStateVariable'].text.strip

      arguments << [direction, name, variable]
    end if argument_list

    arguments
  end

  ##
  # Extracts service actions from +action_list+

  def parse_actions(action_list)
    @actions = {}

    action_list.each_element 'action' do |action|
      name = action.elements['name'].text.strip

      raise Error, "insecure action name #{name}" unless name =~ /\A\w*\z/


      @actions[name] = parse_action_arguments action.elements['argumentList']
    end
  end

  ##
  # Extracts a list of allowed values from +state_variable+

  def parse_allowed_value_list(state_variable)
    list = state_variable.elements['allowedValueList']

    return nil unless list

    values = []

    list.each_element 'allowedValue' do |value|
      value = value.text.strip
      raise Error, "insecure allowed value #{value}" unless value =~ /\A\w*\z/
      values << value
    end

    values
  end

  ##
  # Extracts an allowed value range from +state_variable+

  def parse_allowed_value_range(state_variable)
    range = state_variable.elements['allowedValueRange']

    return nil unless range

    minimum = range.elements['minimum']
    maximum = range.elements['maximum']
    step    = range.elements['step']

    range = [minimum, maximum, step]

    range.map do |value|
      value = value.text
      value =~ /\./ ? Float(value) : Integer(value)
    end
  end

  ##
  # Parses a service description from the scpd_url

  def parse_service_description
    description = REXML::Document.new open(@scpd_url)

    validate_scpd description

    parse_actions description.elements['scpd/actionList']

    service_state_table = description.elements['scpd/serviceStateTable']
    parse_service_state_table service_state_table
  end

  ##
  # Extracts state variables from +service_state_table+

  def parse_service_state_table(service_state_table)
    @variables = {}

    service_state_table.each_element 'stateVariable' do |var|
      name = var.elements['name'].text.strip
      data_type = Types::MAP[var.elements['dataType'].text.strip]
      default = var.elements['defaultValue']

      if default then
        default = default.text.strip
        raise Error, "insecure default value #{default}" unless
          default =~ /\A\w*\z/
      end

      allowed_value_list  = parse_allowed_value_list var
      allowed_value_range = parse_allowed_value_range var

      @variables[name] = [
        data_type,
        default,
        allowed_value_list,
        allowed_value_range
      ]
    end
  end

  ##
  # Returns true for this service's actions as well as the usual behavior

  def respond_to?(message)
    @driver.methods(false).include? message.to_s || super
  end

  ##
  # Ensures +service_description+ has the correct namespace, root element, and
  # version numbers.  Raises an exception if the service isn't valid.

  def validate_scpd(service_description)
    namespace = service_description.elements["//scpd"].namespace

    raise Error, "invalid namespace #{namespace}" unless
      namespace == 'urn:schemas-upnp-org:service-1-0'

    major = service_description.elements["//scpd/specVersion/major"].text.strip
    minor = service_description.elements["//scpd/specVersion/minor"].text.strip

    raise Error, "invalid version #{major}.#{minor}" unless
      major == '1' and minor == '0'
  end

end

