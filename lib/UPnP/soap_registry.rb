require 'UPnP'
require 'soap/mapping/registry'
require 'soap/mapping/encodedregistry'

##
# UPnP relies on the client to do type conversions.  This registry casts the
# SOAPString returned by the service into the real SOAP type so soap4r can
# make the conversion.

class UPnP::SOAPRegistry < SOAP::Mapping::EncodedRegistry

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
