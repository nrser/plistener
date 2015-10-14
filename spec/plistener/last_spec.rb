
require 'digest/sha1'
require 'spec_helper'

describe "Plistener#last" do
  include_context "fresh"

  it "returns nil when there are no changes" do
    plnr = Plistener.new WORKING_DIR
    expect( plnr.last FILEPATH ).to be nil
  end

  it "returns the version in the data folder when no changes" do
    defaults_write 'x', 'ex'
    expect( File.zero? FILEPATH ).to be false
    time = File.mtime FILEPATH
    expect_defaults_read 'x', eq('ex'), type: 'string'
    plnr = Plistener.new WORKING_DIR, paths: PATHS
    plnr.scan
    expect( plnr.last(FILEPATH) ).to eq plnr.version_path(time, FILEPATH)
  end

  it "returns the last changed version when there are changes" do
    # watch the `tmp/rspec/plists` dir
    plnr = Plistener.new WORKING_DIR, paths: PATHS

    # prime the test plist file
    defaults_write 'x', 'start'

    # make sure it exists
    expect( File.exists? FILEPATH ).to be true

    # get that file's mod time and version path
    initial_version_time = File.mtime FILEPATH
    initial_version_path = plnr.version_path initial_version_time, FILEPATH

    # scan that in
    plnr.scan

    # we should have the version in there now
    expect( File.exists? initial_version_path ).to be true

    (1..3).each do |i|
      # wait a sec (mtime is second accurate), then change that file
      sleep 1.1
      defaults_write 'x', "change #{ i }"

      # get the new mod time and version path
      changed_version_time = File.mtime FILEPATH
      changed_version_path = plnr.version_path changed_version_time, FILEPATH

      # it should be later
      expect( changed_version_time ).to be > initial_version_time

      # tell Plistener it changed
      plnr.send :modified, FILEPATH

      # the new version path should exist
      expect( File.exists? changed_version_path ).to be true

      # last should return the changed path
      expect( plnr.last FILEPATH ).to eq changed_version_path
    end
  end # it returns the last changed version when there are changes
end # Plistener#last
