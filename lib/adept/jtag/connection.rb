
require 'adept'
require 'adept/low_level'
require 'adept/jtag'

module Adept
  module JTAG

    #
    # Represents a connection to a JTAG device.
    #
    class Connection 
      extend ConnectionProvider

      attr_reader :tap_state

      #
      # Sets up a new JTAG connection.
      #
      def initialize(device, port_number=0)

        #Store the information regarding the owning device...
        @device = device

        #Initialize the chain to zero until enumeration occurs.
        @chain_length = 0
        @devices_in_chain = 0

        #... open a JTAG connection.
        LowLevel::JTAG::EnableEx(@device.handle, port_number)

      end

      #
      # Closes the given JTAG connection.
      #
      def close
        LowLevel::JTAG::Disable(@device.handle)
      end

      #
      # Returns a list of the JTAG IDCodes for all connected devices.
      #
      def connected_devices

        #Reset all targets' TAPs; this will automatically load the IDCODE instruction into the
        #instruction register
        reset_target

        devices = []
        chain_length = 0
        devices_in_chain = 0

        #Loop until we've enumerated all devices in the JTAG chain.
        loop do

          #Recieve a single 32-bit JTAG ID code, LSB first.
          idcode = receive_data(32, true)

          #If we've recieved the special "null" IDcode, we've finished enumerating.
          #(In this case, we'll choose to accept the technically-valid all-ones IDcode as null,
          #as it is returned by most system boards when their power is turned off, and isn't
          #otherwise supported.)
          break if idcode == "\x00\x00\x00\x00" or idcode == "\xFF\xFF\xFF\xFF"

          #Otherwise, add this idcode to the list...
          devices << JTAG::Device.from_idcode(idcode.reverse, self, devices_in_chain, chain_length)

          #... add its width the the known scan-chain length
          chain_length += devices.last.instruction_width
          devices_in_chain += 1

        end

        #Update the internal chain-length.
        @chain_length = chain_length
        @devices_in_chain = devices_in_chain

        #Return the list of IDCodes.
        devices.reverse

      end

      #
      # Sets the state of the target's Test Access Port.
      #
      def tap_state=(new_state)

        #If we're trying to enter the reset state, force a reset of the test hardware.
        #(This ensure that we can reset the test hardware even if a communications (or target) error
        # causes improper behavior.)
        reset_target if new_state == JTAG::TAPStates::Reset

        #If we're already in the desired state, abort.
        return if new_state == @tap_state

        #Find the correct sequence of TMS values to reach the desired state...
        path = path_to_state(new_state).reverse
        tms_values = [path.to_i(2)]

        #... and apply them.
        LowLevel::JTAG::transmit(@device.handle, tms_values, false, path.length, false)

        #Update the internal record of the TAP state.
        @tap_state = new_state

      end

      #
      # Transmit an instruction over the JTAG test access lines, to be placed into
      # the JTAG instruction register.
      #
      # bytes:     A byte-string which contains the instruction to be transmitted.
      # bit_count: The total amount of bits to be transmitted from the byte string.
      #
      # pad_to_chain_length:
      #   If set, the transmitted data will be suffixed with logic '1's until the chain length has been met.
      #   This allows the transmitter to easily put devices to the "left" of  afttarget device into bypass.
      #
      # prefix_with_ones:
      #   Prefixes the transmitted data with the specified amount of logic '1's. Prefixing is skipped if this parameter
      #   is not provided, or is set to zero. This allows the transmitter to easily put devices to the "right" of a
      #   target device into bypass.
      #
      # do_not_finish: 
      #   If set, the device will be left in the ShiftIR state, so additional instructions data be transmitted.
      #
      def transmit_instruction(bytes, bit_count, pad_to_chain_length=false, prefix_with_ones=0, do_not_finish=false)

        #If the pad-to-chain length option is selected, compute the total amount of padding required.
        #Otherwise, set the required padding to zero.
        padding_after = pad_to_chain_length ? [@chain_length - prefix_with_ones - bit_count, 0].max : 0

        #Move to the Exit1IR state after transmission, allowing the recieved data to be processed,
        #unless the do_not_finish value is set.
        state_after = do_not_finish ? nil : TAPStates::Exit1IR

        #Transmit the actual instruction.
        transmit_in_state(TAPStates::ShiftIR, bytes, bit_count, state_after, true, prefix_with_ones, padding_after)

      end

      #
      # Transmit data over the JTAG test access lines, to be placed into
      # the JTAG data register.
      #
      # bytes:     A byte-string which contains the instruction to be transmitted.
      # bit_count: The total amount of bits to be transmitted from the byte string.
      #
      # pad_to_chain_length:
      #   If set, the transmitted data will be suffixed with logic '1's until the chain length has been met,
      #   *assuming that all devices other than the single target device are in bypass*.
      #   This allows the transmitter to easily fill the bypass registers of all additional devices with zeroes.
      #
      # prefix_with_zeroes:
      #   Prefixes the transmitted data with the specified amount of logic '0's. Prefixing is skipped if this parameter
      #   is not provided, or is set to zero. 
      #
      # do_not_finish: 
      #   If set, the device will be left in the ShiftIR state, so additional instructions data be transmitted.
      #
      def transmit_data(bytes, bit_count, pad_to_chain_length=false, prefix_with_zeroes=0, do_not_finish=false)

        #If the pad-to-chain length option is selected, compute the total amount of padding required.
        #Otherwise, set the required padding to zero.
        padding_after = pad_to_chain_length ? [@devices_in_chain - prefix_with_zeroes - 1, 0].max : 0

        #Move to the Exit1IR state after transmission, allowing the recieved data to be processed,
        #unless the do_not_finish value is set.
        state_after = do_not_finish ? nil : TAPStates::Exit1DR

        #Transmit the actual instruction.
        transmit_in_state(TAPStates::ShiftDR, bytes, bit_count, state_after, false, prefix_with_zeroes, padding_after)

      end


      #
      # Recieve data from the JTAG data register.
      #
      # bit_count: The amount of bits to receive.
      # do_not_finish: If set, the transmission will be "left open" so additional data can be received.
      #
      def receive_data(bit_count, do_not_finish=false, overlap=false)

        #Put the device into the desired state.
        self.tap_state = JTAG::TAPStates::ShiftDR

        #Transmit the data, and recieve the accompanying response.
        response = LowLevel::JTAG::receive(@device.handle, false, false, bit_count, overlap)

        #If a state_after was provided, place the device into that state.
        self.tap_state = JTAG::TAPStates::Exit1DR unless do_not_finish

        #Return the received response.
        response

      end

      #
      # Switches to run/test mode, and holds that state for the desired amount of clock ticks.
      #
      def run_test(clock_ticks)

        #Put the target into the Run-Test-Idle state.
        self.tap_state = JTAG::TAPStates::Idle

        #And "tick" the test clock for the desired amount of cycles.
        LowLevel::JTAG::tick(@device.handle, false, false, clock_ticks, false)

      end

      #
      # Force-resets the target device.
      #
      def reset_target

        #Reset the target device's JTAG controller by sending five bits of TMS='1'.
        LowLevel::JTAG::tick(@device.handle, true, false, 5)

        #Set the internal TAP state to reset.
        @tap_state = JTAG::TAPStates::Reset

      end

      #
      # Registers a device type to be handled by JTAG connections, allowing JTAGDevice
      # instances to be automatically created upon device enumeration.
      # 
      # Device types typically are classes which include the JTAGDevice mixin,
      # 
      #
      def self.register_device_type(type)
        @device_types << type
      end

      #
      # Determines if the given device can serve as the host for a JTAG connection.
      #
      def self.supported_by?(device)
        LowLevel::JTAG::supported?(device)
      end

      private

      #
      # Transmits a sequence of data while in a given state.
      #
      # bytes:     A byte-string which contains the instruction to be transmitted; 
      #            or a boolean value to send a single bit repeatedly.
      # bit_count: The total amount of bits to be transmitted.
      #
      #
      def transmit_in_state(state_before, value, bit_count, state_after=nil, pad_with=false, pad_before=0, pad_after=0)

        #Put the device into the desired state.
        self.tap_state = state_before

        #If we've been instructed to pad before the transmission, do so.
        LowLevel::JTAG::transmit(@device.handle, false, pad_with, pad_before) unless pad_before.zero?

        #Transmit the data, and receive the accompanying response.
        response = transmit_and_advance(false, value, bit_count, pad_after.zero?() ? state_after : nil)

        #If we've been instructed to pad after the transmission, do so.
        transmit_and_advance(false, pad_with, pad_after, state_after) unless pad_after.zero?

        #If a state_after was provided, place the device into that state.
        self.tap_state = state_after unless state_after.nil?

        #Return the received response.
        response

      end

      #
      # Performs a data transmission, and advances TMS.
      #
      # The final TMS value is overlapped with the last bit, so the final shift and
      # state change occur on the same clock edge.
      #
      # tms: The TMS value to use for all but the last bit of the transmission.
      # tdi: The TDI values to transmit, in the same format accepted by the other transmit functions.
      # bit_count: The total amount of bits to transmit.
      # advance_towards:
      #   The state to advance towards after the transmission is complete. Used to
      #   determine the last value of TMS. If advance_towards is nil, the TAP state
      #   will not be advanced- this is useful for conditionally advancing the state.
      #
      def transmit_and_advance(tms, tdi, bit_count, advance_towards)

        #If we don't have a state to advance towards, perform a normal transmit, and return.
        unless advance_towards
          return LowLevel::JTAG::transmit(@device.handle, tms, tdi, bit_count, false)
        end

        #If we were passed a byte array, pack it into a string
        tdi = tdi.pack("C*") if tdi.respond_to?(:pack)

        #Transmit all but the last bit of the TDI data.
        main_response = LowLevel::JTAG::transmit(@device.handle, tms, tdi, bit_count - 1, false) 

        #Figure out what TMS should be during the last transmission by checking the path
        #to the state we want to advance towards.
        last_tms, next_state = @tap_state.next_hop_towards(advance_towards)

        #Transmit the last bit of the TDI data, with the final TMS value. 
        last_tdi = bit_of_message(tdi, bit_count - 1)
        last_response = LowLevel::JTAG::transmit(@device.handle, last_tms == 1, last_tdi, 1, false)

        #Update the internal TAP fsm.
        @tap_state = next_state

        #Compose a single byte-string response by merging the response from the 
        #first and second transmissions.
        return add_bit_to_message(main_response, bit_count - 1, last_response)

      end

      #
      # Returns the appropriate bit of a given message.
      #
      def bit_of_message(string, bit_number) 

        #If were passed a non-unpackable element, return it directly.
        return string unless string.respond_to?(:unpack)

        #Break the message down into an array of bytes
        bytes = string.unpack("B*").first

        #... and return the requested bit, as a boolean.
        bytes[-bit_number - 1] == "1"

      end

      #
      # Appends a given bit to a message.
      # 
      # message: The message to which the bit is to be appended, as a byte-string.
      # message_length: The message's length, in bits.
      # bit: The bit to be appended, as a boolean.
      #
      def add_bit_to_message(message, message_length, bit)

        #If we don't have a message, return the bit as a string.
        return bit ? "\x01" : "\x00" if message_length.zero?

        #If we have something other than an integer, consider its truthiness
        #in the same way that C would.
        bit = bit.unpack("C*").first.nonzero? if bit.respond_to?(:unpack)

        #Convert the message into a sequence of binary bits.
        message = message.unpack("B*").first

        #Ensure that the message is zero-padded to be at least the message length.
        message = message.rjust(message_length, '0')

        #Extract all of the bits up to the bit count, and add the new bit.
        message = (bit ? '1' : '0') + message[-message_length..-1]

        #Convert the message back into a packed string, and return it.
        [message].pack("B*")

      end

      #
      # Find the shortest "path" (sequence of most-select values) which will
      # put the JTAG TAP FSM into the desired state.
      #
      # Note that the next-hop-towards algorithms do not consider "impossible"
      # combinations, such as a jump from EXIT1DR to EXIT2DR; these may cause
      # an infinite loop.
      #
      def path_to_state(destination, start=nil)

        #Create a "state pointer", which will be used to trace the FSM in order to
        #find a path to the destination state. If no start was provided, use the
        #current TAP state.
        state = start || @tap_state

        path = ""

        #Traverse the FSM until we reach our destination.
        until state == destination

          #Find the next hop on the path to the destination...
          next_hop, _ = state.next_hop_towards(destination)

          #Move the "state pointer" to the next state, simulating a traversal
          #of the Finite State Machine.
          state = state.next_state(next_hop)

          #And add the hop to the path
          path << next_hop.to_s

        end

        #And return the computed path.
        path

      end
    end
  end
end
