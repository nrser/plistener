require 'fileutils'

require 'nrser/extras'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'plistener'

ROOT = NRSER.git_root(__FILE__).to_s
TMP = "#{ ROOT }/tmp"
WORKING_DIR = "#{ TMP }/rspec"
DOMAIN = "com.nrser.plistener.test"
FILEPATH = "#{ WORKING_DIR }/plists/#{ DOMAIN }.plist"
LOGFILE = "#{ WORKING_DIR }/log.txt"
FileUtils.mkdir_p File.dirname(LOGFILE)
PATHS = [File.dirname(FILEPATH)]
CONFIG_FILE = "#{ WORKING_DIR }/config.yml"

LEVELS = {
  Logger::DEBUG => [:debug, 'DEBUG'],
  Logger::INFO => [:info, 'INFO'],
  Logger::WARN => [:warn, 'WARN'],
  Logger::ERROR => [:error, 'ERROR'],
  Logger::FATAL => [:fatal, 'FATAL'],
  Logger::UNKNOWN => [:unknown, 'UNKNOWN'],
}

BAD_LEVELS = [:blah, -1, 6, "BLAH"]

File.open(CONFIG_FILE, 'w') do |f|
  f.write YAML.dump({
    'paths' => PATHS.map {|_| _.to_s}
  })
end

def create_plistener
  Plistener.new WORKING_DIR, paths: PATHS
end

def debug *args
  Plistener.debug *args
end

def start_thread
  Plistener.debug "starting thread..."
  plnr = create_plistener
  thread = Thread.new do
    Thread.current[:plnr] = plnr
    plnr.run
    plnr
  end
  thread.abort_on_exception = true
  debug "waiting for instance to fire up..."
  sleep 0.1 until plnr.listening
  debug "instance is listening."
  [thread, plnr]
end

def run_spawn
  debug "spawning plistener..."
  cmd = Cmds.sub "bundle exec plistener run %{dir} --trace", [], dir: WORKING_DIR
  begin
    pid = spawn cmd
    debug "pid is #{ pid }."
    yield
  ensure
    debug "killing process #{ pid }..."
    Process.kill "TERM", pid
    debug "dead."
  end
end

def run
  thread = start
  yield
  thread.kill
end

def write_config path, hash
  File.open(path, 'w') do |f|
    f.write YAML.dump(hash)
  end
end

def defaults_write key, value, options = {}
  options = {
    path: FILEPATH,
    type: "string",
  }.merge options

  Cmds! "defaults write %{path} %{key} %{type} %{value}",
    path: options[:path],
    key: key,
    type: "-#{ options[:type] }",
    value: value
end

def expect_defaults_read key, matcher, options = {}
  options = {
    path: FILEPATH,
    type: nil,
  }.merge options

  expect(
    Cmds.chomp! 'defaults read %{path} %{key}',
      path: options[:path],
      key: key
  ).to matcher

  unless options[:type].nil?
    expect(
      Cmds.chomp! 'defaults read-type %{path} %{key}',
        path: options[:path],
        key: key
    ).to eq "Type is #{ options[:type] }"
  end
end

shared_context "fresh" do
  before(:each) {
    # Plistener.configure_logger level: 0, dest: LOGFILE.open('w')
    # `defaults delete #{ FILEPATH } 2>&1 > /dev/null`
    # `defaults -currentHost delete #{ FILEPATH } 2>&1 > /dev/null`
    # ['changes', 'data', 'plists'].each do |dirname|
    #   path = "#{ WORKING_DIR }/#{ dirname }"
    #   FileUtils.rm_r path if File.exists? path
    #   FileUtils.mkdir_p path
    # end

    # remove and re-create the working dir
    FileUtils.rm_r WORKING_DIR if File.exists? WORKING_DIR
    FileUtils.mkdir_p WORKING_DIR

    # clear out any Plistener ENV vars
    ENV.each do |key, value|
      ENV.delete key if key.start_with? "PLISTENER_"
    end
  }

  let(:plnr) { Plistener.new WORKING_DIR, paths: PATHS }
end
