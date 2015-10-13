
require 'digest/sha1'
require 'spec_helper'

describe "Plistener#last" do
  include_context "fresh"

  it "returns nil when there are no changes" do
    expect( plnr.last FILEPATH ).to be nil
  end

  it "returns the version in the data folder when no changes" do
    `defaults write #{ FILEPATH } x 1`
    expect( File.zero? FILEPATH ).to be false
    expect( `defaults read #{ FILEPATH } x`.chomp ).to eq "1"
    hash = Digest::SHA1.hexdigest File.read(FILEPATH)
    plnr.scan
    expect( plnr.last(FILEPATH)['file_hash'] ).to eq hash
  end

  # it "return the last changed version when there are changes" do
  #   `defaults write #{ FILEPATH } x 8888`
  #
  #   thread, plnr = start
  #
  #   debug "starting writes..."
  #   file_hashes = (0..5).map do |i|
  #     sleep 1
  #
  #     v = rand
  #     debug "writing x = #{ v }"
  #     `defaults write #{ FILEPATH } x #{ v }`
  #     file_hash = Digest::SHA1.hexdigest File.read(FILEPATH)
  #     version_path = plnr.version_path(FILEPATH, file_hash)
  #     debug "file written",
  #       file_hash: file_hash,
  #       version_path: version_path
  #     attempt = 0
  #     while (attempt < 10) && (File.exists?(version_path) == false)
  #       sleep 0.5
  #       attempt += 1
  #       debug "waiting... (attempt #{ attempt })"
  #     end
  #     expect( File.exists?(version_path) ).to be true
  #     file_hash
  #   end
  #
  #   debug file_hashes: file_hashes
  #
  #   sleep 1
  #
  #   expect( Dir["#{ plnr.changes_dir }/*.yml"].length ).to eq(file_hashes.length - 1)
  #
  #   debug "killing thread."
  #   thread.kill
  # end

  # it "return the last changed version when there are changes" do
  #   `defaults write #{ FILEPATH } x 8888`
  #   file_hash = Digest::SHA1.hexdigest File.read(FILEPATH)
  #   plnr = create_plistener
  #   version_path = plnr.version_path FILEPATH, file_hash
  #
  #   run_spawn do
  #
  #     until File.exists? version_path
  #       debug "waiting..."
  #       sleep 0.5
  #     end
  #
  #     debug "file found."
  #
  #     debug "starting writes..."
  #     file_hashes = (0..5).map do |v|
  #       debug "writing x = #{ v }..."
  #       `defaults write #{ FILEPATH } x #{ v }`
  #       file_hash = Digest::SHA1.hexdigest File.read(FILEPATH)
  #       version_path = plnr.version_path(FILEPATH, file_hash)
  #       debug "file written",
  #         file_hash: file_hash,
  #         version_path: version_path
  #       attempt = 0
  #       while (attempt < 5) && (File.exists?(version_path) == false)
  #         sleep 0.5
  #         attempt += 1
  #         debug "waiting for x = #{ v } change... (attempt #{ attempt })"
  #       end
  #       # need to give it a sec to write the change file:
  #       sleep 0.5
  #       expect( File.exists?(version_path) ).to be true
  #       expect( plnr.last(FILEPATH)['file_hash'] ).to eq file_hash
  #       file_hash
  #     end
  #   end
  # end

  it "return the last changed version when there are changes" do
    `defaults write #{ FILEPATH } x 8888`
    plnr.scan
    (0..5).map do |value|
      sleep 0.1
      `defaults write #{ FILEPATH } x #{ value }`
      file_hash = Digest::SHA1.hexdigest File.read(FILEPATH)

      plnr.send :modified, Plistener::CurrentPlist.new(plnr.data_dir, FILEPATH.to_s)

      # the version path file should now exist
      version_path = plnr.version_path FILEPATH, file_hash
      expect( File.exists? version_path ).to be true

      # it should be the last modified
      expect(
        File.basename(
          Dir["#{ File.dirname(version_path) }/*.yml"].max_by {|_| File.mtime(_)},
          '.yml'
        )
      ).to eq file_hash

      # it should come up as #last
      last = plnr.last FILEPATH
      expect( last ).to be_a Hash
      expect( last['file_hash'] ).to eq file_hash
    end
  end
end # Plistener#last
