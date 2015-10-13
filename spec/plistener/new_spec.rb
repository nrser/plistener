require 'spec_helper'

describe "Plistener#new" do
  include_context "fresh"

  def expand paths
    paths.map {
      |fp| File.expand_path fp
    }
  end

  it "loads defaults when no config is present" do
    plnr = Plistener.new WORKING_DIR

    expect( plnr.config_path ).to eq "#{ WORKING_DIR }/config.yml"
    expect( plnr.paths ).to eq expand(Plistener::DEFAULT_PATHS)
    expect( plnr.keep_minutes ).to eq Plistener::DEFAULT_KEEP_MINUTES
  end

  it "loads config from options" do
    options = {
      paths: ["path/one", "path/two"],
      keep_minutes: 10,
    }
    plnr = Plistener.new WORKING_DIR, options
    expect( plnr.paths ).to eq expand(options[:paths])
    expect( plnr.keep_minutes ).to eq options[:keep_minutes]
  end

  it "loads from ENV variables" do
    paths = ["path/one", "path/two"]
    ENV['PLISTENER_PATHS'] = paths.join(':')
    ENV['PLISTENER_KEEP_MINUTES'] = "10"
    plnr = Plistener.new WORKING_DIR
    expect( plnr.paths ).to eq expand(paths)
    expect( plnr.keep_minutes ).to eq 10
  end

  it "loads from a config file in the default location" do
    # keys need to be strings
    config = {
      'paths' => ["path/one", "path/two"],
      'keep_minutes' => 10,
    }
    File.open("#{ WORKING_DIR }/config.yml", 'w') do |f|
      f.write YAML.dump(config)
    end
    plnr = Plistener.new WORKING_DIR
    expect( plnr.paths ).to eq expand(config['paths'])
    expect( plnr.keep_minutes ).to eq config['keep_minutes']
  end

  context "custom config file location" do
    path = "#{ WORKING_DIR }/custom_config.yml"
    config = {
      'paths' => ["path/one", "path/two"],
      'keep_minutes' => 10,
    }

    it "loads from a config file at a custom location option" do
      options = {
        config_path: path,
      }
      write_config path, config
      plnr = Plistener.new WORKING_DIR, options

      expect( plnr.paths ).to eq expand(config['paths'])
      expect( plnr.keep_minutes ).to eq config['keep_minutes']
    end

    it "loads from a config file at a custom location env var" do
      ENV['PLISTENER_CONFIG_PATH'] = path
      write_config path, config
      plnr = Plistener.new WORKING_DIR

      expect( plnr.paths ).to eq expand(config['paths'])
      expect( plnr.keep_minutes ).to eq config['keep_minutes']
    end

    it "raises a ConfigError when a custom file is not found" do
      options = {
        config_path: path,
      }

      expect {
        Plistener.new WORKING_DIR, options
      }.to raise_error Plistener::Error::ConfigError

      ENV['PLISTENER_CONFIG_PATH'] = path

      expect {
        Plistener.new WORKING_DIR
      }.to raise_error Plistener::Error::ConfigError
    end
  end
end # Plistener#new
