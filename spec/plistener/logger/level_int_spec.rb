require 'logger'

require 'spec_helper'

describe 'Plistener::Logger.level_int' do
  it "translates level ints, names and symbols" do
    LEVELS.each do |int, (sym, name)|
      expect( Plistener::Logger.level_int int ).to eq int
      expect( Plistener::Logger.level_int sym ).to eq int
      expect( Plistener::Logger.level_int name ).to eq int
    end
  end

  it "pukes on bad a args" do
    BAD_LEVELS.each do |arg|
      expect {
        Plistener::Logger.level_int arg
      }.to raise_error ArgumentError
    end
  end

end
