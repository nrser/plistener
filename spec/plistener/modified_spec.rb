require 'spec_helper'

describe "Plistener#modified" do
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
      # do a scan to get the inital version in
      plnr.scan

      # get it's info
      initial_version_path = plnr.last FILEPATH
      initial_version_time = File.mtime initial_version_path

      # wait a bit
      sleep 1

      # update the file
      defaults_write 'x', 'oh'

      # do the mod
      plnr.modified FILEPATH

      # get the changes
      changes = plnr.changes

      # there should be one change
      expect( changes.length ).to eq 1
      change = changes[0]

      # it should be for the filepath
      expect( change['path'] ).to eq FILEPATH

      # it should be of type 'modified'
      expect( change['type'] ).to eq 'modified'

      # prev should point to the intial version
      expect( change['prev'] ).to be_instance_of Hash
      expect( change['prev']['path'] ).to eq initial_version_path
      expect( change['prev']['time'] ).to eq initial_version_time

      # current should point to the last version
      expect( change['current'] ).to be_instance_of Hash
      expect( change['current']['path'] ).to eq plnr.last(FILEPATH)
      expect( change['current']['time'] ).to eq File.mtime(FILEPATH)

      # and have the correct diff
      expect( change['diff'] ).to be_instance_of Array
      expect( change['diff'].length ).to eq 1
      expect( change['diff'][0]['op'] ).to eq 'modify'
      expect( change['diff'][0]['key'] ).to eq 'x'
      expect( change['diff'][0]['from'] ).to eq 'ex'
      expect( change['diff'][0]['to'] ).to eq 'oh'
    end # it adds the change
  end # file exists
end # Plistener#add
