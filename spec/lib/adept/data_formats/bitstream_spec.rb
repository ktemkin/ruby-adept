
require 'date'

require 'adept/data_formats/bitstream'

#
# Tests for the Bitstream file reader.
#
describe Adept::DataFormats::Bitstream do

  #A very simple string which should _technically_ be a valid implementation of the bitstream protocol.
  ValidBitFile = "\x00\x09012345678\x00\x01a\x00\x22design_name.ncd;UserID=0x0123ABCD\x00b\x00\x0C3s250ecp132\x00c\x00\x0B2012/12/29\x00d\x00\x0922:41:50\x00e\x00\x00\x00\x100123456789ABCDEF\x00"
  InvalidBitFile = "\x00\x09012345678\x00\x01b\x00\x0BDesignName\x00c\x00\x09PartName\x00d\x00\x05Date\x00e\x00\x05Time\x00f\x00\x00\x00\x10012345689ABCDEF\x00"

  let(:bitstream_array) { "0123456789ABCDEF".bytes.collect { |b| Adept::DataFormats::Bitstream::send(:reverse_byte, b) } }

  context "when provided with a valid bitstream" do
    subject { Adept::DataFormats::Bitstream.from_string(ValidBitFile) }

    it "should read the header from the start of the subject" do
      subject.header.should == "012345678"
    end

    it "should read the design information from the second field in the file" do
      subject.info.should == "design_name.ncd;UserID=0x0123ABCD"
    end

    it "should read the part number from the third field in the file" do
      subject.part.should == "3s250ecp132"
    end

    it "should read the date from the fourth field of the file" do
      subject.raw_date.should == "2012/12/29"
    end

    it "should read the time from the fifth field of the file" do 
      subject.raw_time.should == "22:41:50"
    end

    it "should read the bitsream itself from the remainder of the file" do
      subject.raw_bitstream.should == "0123456789ABCDEF".unpack("C*")
    end

    describe "#filename" do
      it "should extract the filename from the design information" do
        subject.filename.should == "design_name.ncd"
      end
    end

    describe "#usercode" do 
      it "should extract the usercode from the design information" do
        subject.usercode.should == "0123ABCD"
      end
    end

    describe "#time_created" do
      it "should extract the time and date that the bitstream was created as a ruby DateTime" do
        subject.time_created.should == DateTime.new(2012, 12, 29, 22, 41, 50)
      end
    end

    describe "#to_a" do
      it "should create a valid array equal to the bitstream's contents with each byte reversed." do
        subject.to_a.should == bitstream_array
      end
    end

    describe "#to_s" do
      it "should return the binary data from the bitstream with the header removed" do
        subject.to_s.should == bitstream_array.pack("C*")
      end
    end

  end

  context "when provided with an invalid bitstream" do
    
    it "should raise an exception" do
      expect { Adept::DataFormats::Bitstream.from_string(InvalidBitFile) }.to raise_error(BinData::ValidityError)
    end

  end

  describe "#reverse_byte" do
    subject { Adept::DataFormats::Bitstream }

    it "should correct reverse the bits in a single byte" do
      subject.send(:reverse_byte, 0xF0).should == 0x0F
      subject.send(:reverse_byte, 0xAA).should == 0x55
      subject.send(:reverse_byte, 0xDE).should == 0x7B
    end

  end

end
