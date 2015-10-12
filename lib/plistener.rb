require 'listen'
require 'pp'
require 'hashdiff'
require 'yaml'
require 'fileutils'
require 'digest/sha1'
require 'set'

require 'diffable_yaml'
require 'CFPropertyList'

require 'nrser'

require 'state_mate/adapters/defaults'

require "plistener/version"
require 'plistener/logger'

class Plistener
  include Plistener::Logger::Include
  configure_logger level: ::Logger::DEBUG

  module Error
    class ParseError < StandardError; end
  end

  # little internal wrapper for a current plist file from the system
  class CurrentPlist
    attr_accessor :system_path,
                  :contents,
                  :time,
                  :file_hash,
                  :dir,
                  :versions_dir,
                  :version_path,
                  :version_error_path,
                  :history_path

    def initialize data_dir, system_path
      @system_path        = system_path
      @time               = Time.now
      @contents           = File.read @system_path
      @file_hash          = Digest::SHA1.hexdigest @contents
      @versions_dir       = Plistener.versions_dir data_dir, system_path
      @version_path       = Plistener.version_path data_dir, system_path, @file_hash
      # @version_error_path = version_path
      @history_path       = Plistener.history_path data_dir, system_path
    end

    def data
      if @data.nil?
        @data = if contents.empty?
          {}
        else
          StateMate::Adapters::Defaults.read [@system_path]
          # begin
          #  plist = CFPropertyList::List.new data: @contents
          # rescue Exception => e
          #   raise Plistener::Error::ParseError.new NRSER.unblock <<-END
          #     error parsing #{ @system_path }: #{ e }
          #   END
          # end
          # CFPropertyList.native_types plist.value
        end
      end
      @data
    end
  end

  # class HistoryPlist
  #   def initialize data_dir, system_path, file_hash, time
  #     @system_path = system_path
  #     @time = time
  #     @file_hash = file_hash
  #     @dir                = File.join data_dir,  @system_path
  #     @version_path       = File.join @dir,       "#{ @file_hash }.yml"
  #     @version_error_path = File.join @dir,       "#{ @file_hash }.error.yml"
  #     @history_path       = File.join @dir,       "history.yml"
  #   end

  #   def data
  #     if @data.nil?
  #       @data = YAML.load File.read(version_path)
  #     end
  #     @data
  #   end
  # end

  def self.read plist_path
    # check if the file is empty
    return {} if File.zero? plist_path
    plist = CFPropertyList::List.new file: plist_path
    data = CFPropertyList.native_types plist.value
  end

  def self.versions_dir data_dir, plist_system_path
    File.join data_dir, plist_system_path
  end

  def self.version_path data_dir, plist_system_path, file_hash
    File.join versions_dir(data_dir, plist_system_path), "#{ file_hash }.yml"
  end

  def self.history_path data_dir, plist_system_path
    File.join versions_dir(data_dir, plist_system_path), "history.yml"
  end

  def self.change_filename time, plist_system_path
    # want this to be short and unique-ish
    timestamp = time.strftime('%Y.%m.%d-%H.%M.%s.%L')
    # include the start of the sha1 hash of the system filepath.
    #
    # this is so that several files with the same name changed at
    # once (hopefully) won't produce the same filename, while keeping
    # the overall filename relatively short
    path_hash_start = Digest::SHA1.hexdigest(plist_system_path)[0...7]
    # the filename, which is often significant enough to tell what file
    # you're dealing with
    basename = File.basename(plist_system_path)

    "#{ timestamp }_#{ path_hash_start }_#{ basename }.yml"
  end

  def self.change_path changes_dir, time, plist_system_path
    File.join changes_dir, change_filename(time, plist_system_path)
  end

  def self.run working_dir
    self.new(working_dir).run
  end

  def self.clear working_dir
    self.new(working_dir).clear
  end

  def self.reset working_dir
    self.new(working_dir).reset
  end

  def initialize working_dir
    @working_dir    = File.expand_path working_dir
    @config_path    = File.join working_dir, "config.yml"
    @data_dir       = File.join working_dir, "data"
    @changes_dir    = File.join working_dir, "changes"
    @paths = [
      '~/Library/Preferences',
      '/Library/Preferences',
    ]

    # load_config @config_path
  end

  def versions_dir plist_system_path
    self.class.versions_dir @data_dir, plist_system_path
  end

  def version_path plist_system_path, file_hash
    self.class.version_path @data_dir, plist_system_path, file_hash
  end

  def history_path plist_system_path
    self.class.history_path @data_dir, plist_system_path
  end

  def change_path time, plist_system_path
    self.class.change_path @changes_dir, time, plist_system_path
  end

  def load_config config_path
    unless File.exists? @config_path
      raise "config file #{ @config_path } not found"
    end
    @config = YAML.load File.read(config_path)
    @config['paths'] = Hash[
      @config['paths'].map {|rel, opts|
        [File.expand_path(rel), opts]
      }
    ]
    @config
  end

  def update current_plist
    FileUtils.mkdir_p current_plist.versions_dir

    history = if File.exists? current_plist.history_path
      YAML.load File.read(current_plist.history_path)
    else
      []
    end

    # update history if it's not empty and the last entry isn't this file_hash
    if history.empty? || history.last['file_hash'] != current_plist.file_hash
      history << {
        'time' => current_plist.time,
        'file_hash' => current_plist.file_hash,
      }
      File.open(current_plist.history_path, 'w') do |f|
        f.write YAML.dump(history)
      end
    end

    # if the version path already exists, we've already got it's data
    # recorded in `<file_hash>.yml` in are done here
    return if File.exists? current_plist.version_path

    data = current_plist.data

    File.open(current_plist.version_path, 'w') do |f|
      f.write DiffableYAML.dump(data)
    end
  end

  def version_data system_path, file_hash
    YAML.load File.read(version_path(system_path, file_hash))
  end

  def last system_path
    history_path = history_path system_path
    history = YAML.load File.read(history_path)
    history.last
    # filepath = File.join dir, "#{ entry['file_hash'] }.yml"
    # return nil unless File.exists? filepath
    # hash = YAML.load File.read(filepath)
    # [entry, hash]
  end

  def scan dir
    info "scanning...", dir: dir
    Dir.glob("#{ dir }/**/*.plist", File::FNM_DOTMATCH).each do |system_path|
      begin
        update CurrentPlist.new(@data_dir, system_path)
      rescue Errno::EACCES => e
        # can't read file
        warn "can't read file, skipping.", path: system_path, error: e
      rescue Error::ParseError => e
        # couldn't parse file
        warn "can't parse file, skipping.", path: system_path, error: e
      end
    end
    info "scan complete."
  end

  def record_change current_plist, prev_entry, diff
    change_path = change_path current_plist.time, current_plist.system_path

    if File.exists? change_path
      raise "change path exists: #{ change_path.inspect }"
    end

    File.open(change_path, 'w') do |f|
      f.write YAML.dump(
        'path' => current_plist.system_path,
        'prev' => prev_entry,
        'current' => {
          'time' => current_plist.time,
          'file_hash' => current_plist.file_hash,
        },
        'diff' => diff
      )
    end
  end

  def diff from_hash, to_hash
   HashDiff.diff(from_hash, to_hash).map {|op_chr, key, a, b|
      case op_chr
      when '~'
        {
          'op' => 'change',
          'key' => key,
          'from' => a,
          'to' => b,
        }
      when '+'
        {
          'op' => 'add',
          'key' => key,
          'added' => a,
        }
      when '-'
        {
          'op' => 'remove',
          'key' => key,
          'removed' => a,
        }
      else
        raise "unknown op: #{ op.inspect }"
      end
    }
  end

  def paths
    @paths.map {|path| Pathname.new(path).expand_path}
  end

  def listen
    listener = Listen.to(*paths, only: /\.plist$/) do |mod, add, rem|
      # instantiate Plist for each change, which reads and file_hash's  the
      # contents. do this before any other processing to avoid delays that
      # may pick up additional changes
      mod_plists = mod.map {|path|
        info "file modified", path: path
        CurrentPlist.new @data_dir, path
      }
      add_plists = add.map {|path|
        info "file added", path: path
        CurrentPlist.new @data_dir, path
      }
      rem_plists = rem.map {|path|
        info "file removed", path: path
        CurrentPlist.new @data_dir, path
      }

      # now process the changes
      mod_plists.each {|plist| modified plist}
      add_plists.each {|plist| added plist}
      rem_plists.each {|plist| removed plist}

      # mod.each do |path|
      #   prev_entry, prev_hash = last path
      #   update path
      #   current_entry, current_hash = last path
      #   unless current_entry['file_hash'] == prev_entry['file_hash']
      #     record_change path,
      #                   prev_entry,
      #                   current_entry,
      #                   diff(prev_hash, current_hash)
      #   end
      # end

      # add.each do |path|
      #   update path
      #   current_entry, current_hash = last path
      #   record_change path,
      #                 prev_entry,
      #                 current_entry,
      #                 diff({}, current_hash)
      # end

      # TODO: what about removals???

      cleanup
    end
    listener.start
    sleep
  end

  def cleanup
    minutes = 1
    info "cleaning up changes older than #{ minutes } minutes..."
    limit = Time.now - (60 * minutes)

    old_file_hashes = Set.new
    current_file_hashes = Set.new

    Dir["#{ @changes_dir }/*.yml"].each do |path|
      change = YAML.load File.read(path)
      if change['current']['time'] < limit
        debug "deleting change",
          path: path
        old_file_hashes << [change['path'], change['prev']['file_hash']]
        FileUtils.rm path
      else
        current_file_hashes << [change['path'], change['prev']['file_hash']]
        current_file_hashes << [change['path'], change['current']['file_hash']]
      end
    end

    to_del = old_file_hashes - current_file_hashes

    to_del.each do |path, file_hash|
      FileUtils.rm version_path path, file_hash
    end
  end

  def run
    FileUtils.mkdir_p @data_dir
    FileUtils.mkdir_p @changes_dir
    paths.each do |path, opts|
      scan path
    end
    cleanup
    listen
  end

  def clear
    FileUtils.rm Dir.glob("#{ @changes_dir }/*.yml")
  end

  def reset
    FileUtils.rm_rf Dir.glob("#{ @data_dir }/*")
    clear
  end

  private

  def modified current_plist
    prev_entry = last current_plist.system_path
    # bail if the contents are the same as the last entry
    return if current_plist.file_hash == prev_entry['file_hash']
    # run an update to get the data into the system and record the
    # history
    update current_plist
    # get the data from the previous version
    prev_data = version_data current_plist.system_path, prev_entry['file_hash']
    # do a diff
    diff = diff prev_data, current_plist.data
    # now record a change
    record_change current_plist, prev_entry, diff
  end

  def added current_plist
    update current_plist
    diff = diff {}, current_plist.data
    record_change current_plist, nil, diff
  end

  def removed current_plist
    prev_entry = last current_plist.system_path
    update current_plist
    if prev_entry.nil?
      # we don't know what was there before
      raise "we didn't know anything about file #{ current_plist.system_path.inspect }"
    else
      prev_data = version_data current_plist.system_path, prev_entry['file_hash']
      diff = diff prev_data, current_plist.data
      record_change current_plist, prev_entry, diff
    end
  end
end
