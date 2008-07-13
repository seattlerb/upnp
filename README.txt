= UPnP

* http://seattlerb.org/UPnP
* http://upnp.org
* Bugs: http://rubyforge.org/tracker/?atid=5921&group_id=1513

== DESCRIPTION:

An implementation of the UPnP protocol

== FEATURES/PROBLEMS:

* Client support:
  * Discovers UPnP devices and services via SSDP, see UPnP::SSDP
  * Creates a SOAP RPC driver for discovered services, see
    UPnP::Control::Service
  * Creates concrete UPnP device and service classes that may be extended with
    utility methods, see UPnP::Control::Device::create,
    UPnP::Control::Service::create and the UPnP-IGD gem.
* Server support:
  * Easy creation of device and service skeletons from UPnP specifications
  * Advertises UPnP devices and services via SSDP
  * Creates a SOAP RPC server for each service
  * Mounts services in a single WEBrick server
* Eventing not implemented

== SYNOPSIS:

See UPnP::Device for instructions on creating a UPnP device.

See UPnP::Service for instructinos on creating a UPnP service.

Print out information about UPnP devices nearby:

  upnp_discover

Listen for UPnP resource notifications:

  upnp_listen

Search for root UPnP devices and print out their description URLs:

  require 'UPnP/SSDP'
  
  resources = UPnP::SSDP.new.search :root
  locations = resources.map { |resource| resource.location }
  puts locations.join("\n")

Create a UPnP::Control::Device from the first discovered root device:

  require 'UPnP/control/device'
  
  device = UPnP::Control::Device.create locations.first

Enumerate actions on all services on the device:

  service_names = device.services.map do |service|
    service.methods(false)
  end
  
  puts service_names.sort.join("\n")

Assuming the root device is an InternetGatewayDevice with a WANIPConnection
service, print out the external IP address for the gateway:

  wic = device.services.find { |service| service.type =~ /WANIPConnection/ }
  puts wic.GetExternalIPAddress

== REQUIREMENTS:

* UPnP devices

== INSTALL:

  sudo gem install UPnP

== LICENSE:

Original code copyright 2008 Eric Hodel.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the names of the authors nor the names of their contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

