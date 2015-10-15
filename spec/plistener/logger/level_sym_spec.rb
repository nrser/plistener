require 'logger'

require 'spec_helper'

describe 'Plistener::Logger.level_sym' do
  it "translates level syms, names and symbols" do
    LEVELS.each do |int, (sym, name)|
      expect( Plistener::Logger.level_sym sym ).to eq sym
      expect( Plistener::Logger.level_sym int ).to eq sym
      expect( Plistener::Logger.level_sym name ).to eq sym
    end
  end

  it "pukes on bad a args" do
    BAD_LEVELS.each do |arg|
      expect {
        Plistener::Logger.level_sym arg
      }.to raise_error ArgumentError
    end
  end

end
