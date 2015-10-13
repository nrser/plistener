require 'fileutils'

require 'nrser/extras'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'plistener'

ROOT = NRSER.git_root(__FILE__).to_s
TMP = "#{ ROOT }/tmp"
WORKING_DIR = "#{ TMP }/rspec"
DOMAIN = "com.nrser.plistener.test"
# FILEPATH = File.expand_path "~/Library/Preferences/#{ DOMAIN }.plist"
FILEPATH = "#{ WORKING_DIR }/plists/#{ DOMAIN }.plist"
LOGFILE = "#{ WORKING_DIR }/log.txt"
FileUtils.mkdir_p File.dirname(LOGFILE)
PATHS = [File.dirname(FILEPATH)]
CONFIG_FILE = "#{ WORKING_DIR }/config.yml"

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
end
