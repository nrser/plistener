require 'spec_helper'

describe "Plistener#added" do
  include_context "fresh"

  it "raises an Errno::ENOENT error if the file doesn't exist" do
    expect { plnr.added FILEPATH }.to raise_error Errno::ENOENT
  end

  context "legit file exists" do
    before(:each) {
      defaults_write 'x', 'ex'
    }

    it "adds the change" do
      # do the add
      plnr.added FILEPATH

      # get the changes
      changes = plnr.changes

      # there should be one change
      expect( changes.length ).to eq 1

      change = changes[0]

      # it should be for the filepath
      expect( change['path'] ).to eq FILEPATH

      # it should be of type 'added'
      expect( change['type'] ).to eq 'added'

      # prev should be nil
      expect( change['prev'] ).to be nil

      # current should point to the last version
      expect( change['current'] ).to be_instance_of Hash
      expect( change['current']['path'] ).to eq plnr.last(FILEPATH)
      expect( change['current']['time'] ).to eq File.mtime(FILEPATH)

      # and have the correct diff
      expect( change['diff'] ).to be_instance_of Array
      expect( change['diff'].length ).to eq 1
      expect( change['diff'][0]['op'] ).to eq 'add'
      expect( change['diff'][0]['key'] ).to eq 'x'
      expect( change['diff'][0]['added'] ).to eq 'ex'
    end # it adds the change
  end # file exists
end # Plistener#add
