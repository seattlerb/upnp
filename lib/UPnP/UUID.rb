# Original code copyright (c) 2005,2007 Assaf Arkin
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'fileutils'
require 'thread'
require 'tmpdir'
require 'UPnP'

##
# This UUID class is here to make Assaf Arkin's uuid gem not write to $stdout.
# Used under MIT license (see source code).
#
# To generate a UUID:
#
#   UUID.setup
#   uuid = UUID.new
#   uuid.generate

class UPnP::UUID

  ##
  # File holding the NIC MAC address

  NIC_FILE = '~/.UPnP/uuid_mac_address'

  ##
  # Clock multiplier. Converts Time (resolution: seconds) to UUID clock
  # (resolution: 10ns)

  CLOCK_MULTIPLIER = 10000000

  ##
  # Clock gap is the number of ticks (resolution: 10ns) between two Ruby Time
  # ticks.

  CLOCK_GAPS = 100000

  ##
  # Version number stamped into the UUID to identify it as time-based.

  VERSION_CLOCK = 0x0100

  ##
  # Formats supported by the UUID generator.
  #
  # <tt>:default</tt>:: Produces 36 characters, including hyphens separating
  #                     the UUID value parts
  # <tt>:compact</tt>:: Produces a 32 digits (hexadecimal) value with no
  #                     hyphens
  # <tt>:urn</tt>:: Adds the prefix <tt>urn:uuid:</tt> to the
  #                 <tt>:default</tt> format

  FORMATS = {
    :compact => '%08x%04x%04x%04x%012x',
    :default => '%08x-%04x-%04x-%04x-%012x',
    :urn     => 'urn:uuid:%08x-%04x-%04x-%04x-%012x',
  }

  @uuid = nil

  ##
  # Sets up the UUID class generates a UUID in the default format.

  def self.generate(nic_file = NIC_FILE)
    return @uuid.generate if @uuid
    setup nic_file
    @uuid = new
    @uuid.generate
  end

  ##
  # Discovers the NIC MAC address and saves it to +nic_file+.  Works for UNIX
  # (ifconfig) and Windows (ipconfig).

  def self.setup(nic_file = NIC_FILE)
    nic_file = File.expand_path nic_file

    return if File.exist? nic_file

    FileUtils.mkdir_p File.dirname(nic_file)

    # Run ifconfig for UNIX, or ipconfig for Windows.
    config = ''
    Dir.chdir Dir.tmpdir do
      config << `ifconfig 2>/dev/null`
      config << `ipconfig /all 2>NUL`
    end

    addresses = config.scan(/[^:\-](?:[\da-z][\da-z][:\-]){5}[\da-z][\da-z][^:\-]/i)
    addresses = addresses.map { |addr| addr[1..-2] }

    raise Error, 'MAC address not found via ifconfig or ipconfig' if
      addresses.empty?

    open nic_file, 'w' do |io| io.write addresses.first end
  end

  ##
  # Creates a new UUID generator using the NIC stored in NIC_FILE.

  def initialize(nic_file = NIC_FILE)
    if File.exist? nic_file then
      address = File.read nic_file

      raise Error, "invalid MAC address #{address}" unless
        address =~ /([\da-f]{2}[:\-]){5}[\da-f]{2}/i
      @address = address.scan(/[0-9a-fA-F]{2}/).join.hex & 0x7FFFFFFFFFFF
    else
      @address = rand(0x800000000000) | 0xF00000000000
    end

    @drift = 0
    @last_clock = (Time.new.to_f * CLOCK_MULTIPLIER).to_i
    @mutex = Mutex.new
    @sequence = rand 0x10000
  end

  ##
  # Generates a new UUID string using +format+.  See FORMATS for a list of
  # supported formats.

  def generate(format = :default)
    template = FORMATS[format]

    raise ArgumentError, "unknown UUID format #{format.inspect}" if
      template.nil?

    # The clock must be monotonically increasing. The clock resolution is at
    # best 100 ns (UUID spec), but practically may be lower (on my setup,
    # around 1ms). If this method is called too fast, we don't have a
    # monotonically increasing clock, so the solution is to just wait.
    #
    # It is possible for the clock to be adjusted backwards, in which case we
    # would end up blocking for a long time. When backward clock is detected,
    # we prevent duplicates by asking for a new sequence number and continue
    # with the new clock.

    clock = @mutex.synchronize do
      clock = (Time.new.to_f * CLOCK_MULTIPLIER).to_i & 0xFFFFFFFFFFFFFFF0

      if clock > @last_clock then
        @drift = 0
        @last_clock = clock
      elsif clock == @last_clock then
        drift = @drift += 1

        if drift < 10000
          @last_clock += 1
        else
          Thread.pass
          nil
        end
      else
        @sequence = rand 0x10000
        @last_clock = clock
      end
    end while not clock

    template % [
      clock & 0xFFFFFFFF,
      (clock >> 32) & 0xFFFF,
      ((clock >> 48) & 0xFFFF | VERSION_CLOCK),
      @sequence & 0xFFFF,
      @address & 0xFFFFFFFFFFFF
    ]
  end

end

