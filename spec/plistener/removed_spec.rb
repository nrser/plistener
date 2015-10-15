require 'spec_helper'

describe "Plistener#removed" do
  include_context "fresh"

  it "raises a PreviousVersionNotFoundError error if the file doesn't exist" do
    expect {
      plnr.removed FILEPATH
    }.to raise_error Plistener::Error::PreviousVersionNotFoundError
  end

  context "legit file exists" do
    before(:each) {
      defaults_write 'x', 'ex'
    }

    it "adds the change" do
      # scan to get the initial version into the system
      plnr.scan

      # do the remove
      plnr.removed FILEPATH

      # get the changes
      changes = plnr.changes

      # there should be one change
      expect( changes.length ).to eq 1

      change = changes[0]

      # it should be for the filepath
      expect( change['path'] ).to eq FILEPATH

      # it should be of type 'removed'
      expect( change['type'] ).to eq 'removed'

      # prev should point to the last version
      expect( change['prev'] ).to be_instance_of Hash
      expect( change['prev']['path'] ).to eq plnr.last(FILEPATH)
      expect( change['prev']['time'] ).to eq File.mtime(FILEPATH)

      # current should be the last version
      expect( change['current'] ).to be nil

      # and have the correct diff
      expect( change['diff'] ).to be_instance_of Array
      expect( change['diff'].length ).to eq 1
      expect( change['diff'][0]['op'] ).to eq 'remove'
      expect( change['diff'][0]['key'] ).to eq 'x'
      expect( change['diff'][0]['removed'] ).to eq 'ex'
    end # it adds the change
  end # file exists
end # Plistener#add
