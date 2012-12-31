require 'ffi'
require 'adept/lowlevel/adept_library'

module Adept
  module LowLevel

    #
    # Diglient JTAG (DJTG)
    # Wrapper for the low-level JTAG manipulation functions.
    #
    module JTAG
      extend AdeptLibrary

      #Wrap the JTAG library, libDJTG
      wrap_adept_library 'djtg'

      #
      # JTAG Support Query Functions
      #

      #Determines the number of JTAG ports that the given device provides.
      attach_function :DjtgGetPortCount, [:ulong, :pointer], :bool

      #Determines which interfaces the given JTAG port provides.
      attach_function :DjtgGetPortProperties, [:ulong, :int32, :pointer], :bool

      #Bit numbers for the call support functions.
      SUPPORTS_SET_SPEED = 0
      SUPPORTS_SET_PIN_STATE = 1


      #
      # Returns the number of JTAG ports the given device offers.
      # 
      def self.port_count(device)
        
        #Create a pointer to a new Int32 in memory...
        count_pointer = FFI::MemoryPointer.new(:int32)
        
        #... and fill it with the number of available JTAG ports.
        DjtgGetPortCount(device.handle, count_pointer)

        #Return the acquired count as a ruby integer.
        count_pointer.get_int32(0)

      end

      #
      # Returns a true-like value if the given device supports JTAG,
      # or nil if it does not.
      #
      def self.supported?(device)
        port_count(device).nonzero?
      end

      #
      # Returns a hash which indicates the calls that the given port supports.
      # Keys include:
      #   -set_speed, which sets the bit-rate of the JTAG connection.
      #   -set_pins, which sets the values of the JTAG pins directly.
      # 
      def self.supported_calls(device, port_number)
       
        #Create a pointer to a new DWORD...
        properties_pointer = FFI::MemoryPointer.new(:ulong)

        #... and fill it with a bit-vector indicates supports for various system calls.
        DjtgGetPortProperties(device.handle, port_number, properties_pointer)

        #Extract the property bit-vector from the 
        properties = properties_pointer.get_ulong(0)

        #Return a hash which indicates which calls are supported.
        {
          :set_speed => properties[0].nonzero?,
          :set_pins  => properties[1].nonzero?
        }

      end

      #
      # JTAG Enable/Disable calls.
      # 
      
      #Enable the JTAG port with the given number. Only one JTAG device can be active at a time!
      attach_function :DjtgEnableEx, [:ulong, :int32], :bool

      #Disable the currently active JTAG port.
      attach_function :DjtgDisable, [:ulong], :bool

      #
      # JTAG 
      #
      
      attach_function :DjtgPutTdiBits, [:ulong, :bool, :pointer, :pointer, :ulong, :bool], :bool
      attach_function :DjtgPutTmsBits, [:ulong, :bool, :pointer, :pointer, :ulong, :bool], :bool
      attach_function :DjtgPutTmsTdiBits, [:ulong, :pointer, :pointer, :ulong, :bool], :bool
      attach_function :DjtgGetTdoBits, [:ulong, :bool, :bool, :pointer, :ulong, :bool], :bool
      attach_function :DjtgClockTck, [:ulong, :bool, :bool, :ulong, :bool], :bool

      # 
      # //overlapped functions
      # DPCAPI BOOL DjtgPutTdiBits(HIF hif, BOOL fTms, BYTE * rgbSnd, BYTE * rgbRcv, DWORD cbits, BOOL fOverlap);
      # DPCAPI BOOL DjtgPutTmsBits(HIF hif, BOOL fTdi, BYTE * rgbSnd, BYTE * rgbRcv, DWORD cbits, BOOL fOverlap);
      # DPCAPI BOOL DjtgPutTmsTdiBits(HIF hif, BYTE * rgbSnd, BYTE * rgbRcv, DWORD cbitpairs, BOOL fOverlap);
      # DPCAPI BOOL DjtgGetTdoBits(HIF hif, BOOL fTdi, BOOL fTms, BYTE * rgbRcv, DWORD cbits, BOOL fOverlap);
      # DPCAPI BOOL DjtgClockTck(HIF hif, BOOL fTms, BOOL fTdi, DWORD cclk, BOOL fOverlap);
      #
      #




    end

  end
end
