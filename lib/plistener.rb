require 'listen'
require 'pp'
require 'hashdiff'
require 'yaml'
require 'fileutils'
require 'digest/sha1'
require 'diffable_yaml'
require 'CFPropertyList'

class Plistener

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
          plist = CFPropertyList::List.new data: @contents
          CFPropertyList.native_types plist.value
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
    # want this to be short and unique
    [ 
      time.to_i,
      File.basename(plist_system_path),
      Digest::SHA1.hexdigest(plist_system_path)[0...7],
      'yml'
    ].join '.'
  end

  def self.change_path changes_dir, time, plist_system_path
    File.join changes_dir, change_filename(time, plist_system_path)
  end

  def self.run root
    instance = self.new root
    instance.run
  end

  def initialize root
    @root           = File.expand_path root
    @config_path    = File.join root, "config.yml"
    @data_dir       = File.join root, "data"
    @changes_dir    = File.join root, "changes"

    load_config @config_path
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

    # otherwise, we need to try and read the data
    # begin
    #   data = current_entry.data
    # rescue Exception => e
    #   # we ran into a parsing error

    #   # what we want to here is record what happen

    #   trace = "#{e.message} (#{e.class})\n\t#{ e.backtrace.join("\n\t") }"
    #   File.open(errorpath, 'w') do |f|
    #     f.write YAML.dump('trace' => trace, 'contents' => contents)
    #   end

    #   puts 
    #   puts "couldn't read #{ realpath }:"
    #   puts trace
    #   puts
    # else
    #   File.open(filepath, 'w') do |f|
    #     f.write DiffableYAML.dump(hash)
    #   end
    # end
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
    puts "scanning #{ dir.inspect }..."
    Dir.glob("#{ dir }/**/*.plist", File::FNM_DOTMATCH).each do |system_path|
      update CurrentPlist.new(@data_dir, system_path)
    end
    puts "scan complete."
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
    @config['paths'].map {|path, opts| path}
  end

  def listen
    listener = Listen.to(*paths, only: /\.plist$/) do |mod, add, rem|
      # instantiate Plist for each change, which reads and file_hash's  the
      # contents. do this before any other processing to avoid delays that
      # may pick up additional changes
      mod_plists = mod.map {|path| CurrentPlist.new @data_dir, path}
      add_plists = add.map {|path| CurrentPlist.new @data_dir, path}
      rem_plists = rem.map {|path| CurrentPlist.new @data_dir, path}

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
    end
    listener.start
    sleep
  end

  def run
    FileUtils.mkdir_p @data_dir
    FileUtils.mkdir_p @changes_dir
    @config['paths'].each do |path, opts|
      scan path
    end
    listen
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

  def added path, time

  end

  def removed path, time

  end
end
