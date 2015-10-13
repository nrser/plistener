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

using NRSER

class Plistener
  module Refinements
    refine Object do
      def maybe
        yield self unless self.nil?
      end
    end
  end
end

using Plistener::Refinements

# @!attribute [r] paths
#     @return [Array<String>] absolute paths being watched.
#
# @!attribute [r] config_path
#     @return [String] absolute path to load config file from.
class Plistener

  DEFAULT_PATHS = [ '~/Library/Preferences', '/Library/Preferences', ]
  DEFAULT_KEEP_MINUTES = 15

  attr_accessor :paths,
                :config_path,
                :keep_minutes,
                :listening,
                :changes_dir,
                :data_dir,
                :paths

  include Plistener::Logger::Include
  configure_logger level: ::Logger::DEBUG

  # submodules and subclasses
  # ========================

  module Error
    class PlistenerError < StandardError; end
    class ParseError < PlistenerError; end
    class ConfigError < PlistenerError; end
  end

  # class util functions
  # ====================

  # @api util
  # *pure*
  #
  # get a datetime string that we use in filenames. includes milliseconds
  # to reduce change of collisions when stuff is happening quickly.
  #
  # @param time [Time] the time to create the string for.
  #
  # @return [String] string formating of the time.
  #
  def self.time_str time
    time.strftime '%Y.%m.%d-%H.%M.%S.%L'
  end # .time_str


  # @api util
  #
  # uses {StateMate::Adapters::Defautls.read} to read the plist file path.
  #
  # under the hood, this uses `defaults export` to generate XML and
  # then {CFPropertyList} to parse and Ruby-ize it.
  #
  # @param plist_path [String] absolute path to the plist file.
  #
  # @return [Hash] Ruby representation of the property list.
  #
  def self.read plist_path
    # check if the file is empty
    # TODO: not sure if still needed using StateMate
    return {} if File.zero? plist_path
    StateMate::Adapters::Defaults.read [plist_path]
  end # .read


  # @api util
  #
  # @param time [Time] the time to generate the filename for.
  # @param plist_system_path [String] absolute path to the plist on the system.
  #
  # @return [String] the change filename.
  #
  def self.change_filename time, plist_system_path
    # want this to be short and unique-ish
    #
    # include the start of the sha1 hash of the system filepath.
    #
    # this is so that several files with the same name changed at
    # once (hopefully) won't produce the same filename, while keeping
    # the overall filename relatively short
    path_hash_start = Digest::SHA1.hexdigest(plist_system_path)[0...7]
    # the filename, which is often significant enough to tell what file
    # you're dealing with
    basename = File.basename(plist_system_path)

    "#{ time_str time }_#{ path_hash_start }_#{ basename }.yml"
  end

  # @api util
  # *pure*
  #
  # use {HashDiff.diff} to diff two hashes and massage the results a little
  # bit.
  #
  # @param from_hash [Hash] the older version of the hash.
  # @param to_hash [Hash] the newer version of the hash.
  #
  # @return [Array<Hash>] an array of hashes detailing the differences.
  #
  #     each element has a 'op' key with value of 'change', 'add' or 'remove'
  #     and a 'key' key with HashDiff's string representation of the key that
  #     was changed.
  #
  #     'change' elements have 'from' and 'to' keys mapped to the old
  #     and new values for the key.
  #
  #     'add' elements have an 'added' key mapped to the new value for
  #     the key.
  #
  #     'remove' elements have a 'remove' key mapped to the old value
  #     for the key.
  #
  def self.diff from_hash, to_hash
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


  # instance methods
  # ================

  # @api public
  #
  # make a new Plistener.
  #
  # @param working_dir path to the directory to save stuff in. also where
  #     the `config.yml` file is looked for by default.
  #
  # @param options [Hash] configuration options.
  # @option options [Stirng] :config_path ("#{ working_dir }/config.yml")
  #     path to load config file from.
  # @option options [Array<Sting>] :paths
  #     (['~/Library/Preferences', '/Library/Preferences'])
  #     paths to watch.
  # @option options [Fixnum] :keep_minutes (15) positive integer minutes to
  #     keep records for.
  #
  def initialize working_dir, options = {}
    @working_dir    = File.expand_path working_dir
    @config_path    = File.join @working_dir, "config.yml"
    @data_dir       = File.join @working_dir, "data"
    @changes_dir    = File.join @working_dir, "changes"

    default_config_path = "#{ @working_dir }/config.yml"
    @config_path = (
      options[:config_path] ||
      ENV['PLISTENER_CONFIG_PATH'] ||
      default_config_path
    ).pipe {|rel| File.expand_path rel}

    yaml_config = if (
      # something was provided other than the default path
      (@config_path != default_config_path) ||
      # or it exists
      File.exists?(@config_path)
    )
      # if either a config path
      begin
        YAML.load File.read(@config_path)
      rescue Exception => e
        raise Error::ConfigError.new binding.erb <<-END
          could not read config from #{ @config_path }

          error: <%= e.format %>
        END
      end
    else
      # config file does not exist
      {}
    end

    @paths = (
      options[:paths] ||
      ENV['PLISTENER_PATHS'].maybe {|_| _.split(':')} ||
      yaml_config['paths'] ||
      DEFAULT_PATHS
    ).map {|rel| File.expand_path rel }

    @keep_minutes = (
      options[:keep_minutes] ||
      ENV['PLISTENER_KEEP_MINUTES'].maybe {|_| _.to_i} ||
      yaml_config['keep_minutes'] ||
      DEFAULT_KEEP_MINUTES
    )

    @listening = false

    FileUtils.mkdir_p @data_dir
    FileUtils.mkdir_p @changes_dir
  end # #initialize

  # instance util methods
  # =====================

  # @api util
  #
  def versions_dir plist_system_path
    File.join @data_dir, plist_system_path
  end # #versions_dir


  # @api util
  #
  # @param time [Time] the time to generate the file path for.
  # @param plist_system_path [String] absolute path to the plist on the system.
  #
  # @return [String] the change file path.
  #
  def change_path time, plist_system_path
    File.join @changes_dir, self.class.change_filename(time, plist_system_path)
  end


  # @api util
  #
  # get the last time a file was seen.
  #
  # @param system_path [String] absolute path to the plist file.
  #
  # @return [String, nil]
  #     if there is history for the file, the path to the latest version.
  #     otherwise `nil`.
  #
  def last system_path
    debug "calling #last...",
      system_path: system_path
    # # changes is...
    # #
    # # get all the .yml files in the changes dir
    # Pathname.glob("#{ @changes_dir }/*.yml").map {|pathname|
    #   # load them
    #   debug "loading #{ pathname }..."
    #   YAML.load pathname.read
    # }.select {|change|
    #   # pick the ones who's path is the one we're looking for
    #   change['path'] == system_path
    # }.max_by {|change|
    #   # grab the one with the greatest timestamp
    #   change['time']
    # }.pipe {|change|
    #   # return it if we found one.
    #   unless change.nil?
    #     debug "found last via change",
    #       change: change
    #     return {
    #       'file_hash' => change['current']['file_hash'],
    #       'time' => change['current']['time'],
    #     }
    #   end
    #   # otherwise, fall through...
    # }

    versions_dir = versions_dir system_path
    debug "looking in versions dir...", versions_dir: versions_dir

    # now we need to see if there are any versions in the data dir
    path = Dir.glob(
      # grab all the .yml paths in the versions dir
      "#{ versions_dir }/*.plist"
    ).max_by {|path|
      # grab the one with the largest modified time
      File.mtime path
    }

    debug "found", path: path
    path
  end # #last


  # @api util
  #
  # scan the target directories for initial versions of plist files.
  # run before listening.
  #
  # @return nil
  #
  def scan
    paths.each do |dir|
      info "scanning...", dir: dir
      Dir.glob("#{ dir }/**/*.plist", File::FNM_DOTMATCH).each do |system_path|
        # debug "found #{ system_path }"
        begin
          record_version system_path
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

    nil
  end # #scan


  def run
    scan
    prune
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

    # @api private
    #
    # saves the current version of the plist in the data folder.
    #
    # @param system_path [String] absolute path to the `.plist` file on the
    #     system.
    #
    # @return [String] path to the coppied version of the file.
    #
    def record_version system_path
      debug "recording version",
        system_path: system_path

      # get the dir that this plist goes in
      versions_dir = versions_dir system_path

      # make sure the versions directory exists
      FileUtils.mkdir_p versions_dir

      temp_path = "#{ versions_dir }/temp_#{ File.basename system_path }"

      # copy it to a temp filename in the versions dir
      FileUtils.cp system_path, temp_path, preserve: true

      # get the modified time
      time = File.mtime temp_path

      # build the version path
      version_path = "#{ versions_dir }/#{ self.class.time_str time }_#{ File.basename system_path }"

      # rename the file
      FileUtils.cp temp_path, version_path, preserve: true
      FileUtils.rm temp_path

      debug "done recording version.",
        system_path: system_path,
        version_path: version_path

      version_path
    end # #record_version


    # @api private
    #
    # record a change in the `changes` folder.
    #
    # @param system_path [String] absolute path to plist on system.
    #
    # @param current_version_path [String] absolute path to the current version
    #     in the `data` folder.
    #
    # @param prev_version_path [String, nil] absolute path to the previous version
    #     in the `data` folder. may be `nil` if we don't know anything about
    #     previous versions.
    #
    # @param diff [Array<Hash<String, Object>>, nil] the output of {#diff}.
    #     may be `nil` if we don't have a previous version to diff against.
    #
    # @return nil
    #
    def record_change system_path,
                      current_version_path,
                      prev_version_path,
                      diff
      change_path = change_path Time.now, system_path

      if File.exists? change_path
        raise "change path exists: #{ change_path.inspect }"
      end

      change = {
        'path' => system_path,
        'current' => {
          'path' => current_version_path,
          'time' => File.mtime(current_version_path),
        },
        'diff' => diff,
      }

      change['prev'] = prev_version_path.maybe {|prev_version_path|
        {
          'path' => prev_version_path,
          'time' => File.mtime(prev_version_path),
        }
      }

      File.open(change_path, 'w') do |f|
        f.write YAML.dump(change)
      end

      nil
    end # #record_change


    # @api private
    #
    # starts listening
    #
    # @return nil
    #
    def listen
      debug "calling #listen..."

      listener = Listen.to(*paths, only: /\.plist$/) do |mod, add, rem|
        hear mod, add, rem

        begin
          prune
        rescue Exception => e
          error binding.erb <<-END
            exception while pruning old changes and versions:
              error: <%= e.format %>
          END
        end
      end

      listener.start
      @listening = true
      debug "listening..."

      # Trap ^C
      Signal.trap("INT") {
        @listening = false
      }

      # Trap `Kill `
      Signal.trap("TERM") {
        @listening = false
      }

      sleep 0.01 while @listening

      info "stoping listening..."
      listener.stop
      info "done listening."

      nil
    end # #listen


    # @api private
    #
    # respond to files that have changed.
    #
    # @param mod_paths [Array<String>] list of absolute paths that have
    #     been modified.
    #
    # @param add_paths [Array<String>] list of absolute paths that have been
    #     added.
    #
    # @param rem_paths [Array<String>] list of absolute paths that have been
    #     removed.
    #
    # @return nil
    #
    def hear mod_paths, add_paths, rem_paths
      # instantiate Plist for each change, which reads and file_hash's  the
      # contents. do this before any other processing to avoid delays that
      # may pick up additional changes
      mod_plists = mod_paths.map {|system_path|
        info "file modified", system_path: system_path
        begin
          modified system_path
        rescue Exception => e
          error binding.erb <<-END
            exception while processing modified file:
              system_path: <%= system_path %>
              error: <%= e.format %>
          END
        end
      }

      add_plists = add_paths.map {|path|
        info "file added", path: path
        # CurrentPlist.new @data_dir, path
      }
      rem_plists = rem_paths.map {|path|
        info "file removed", path: path
        # CurrentPlist.new @data_dir, path
      }

      # # now process the changes
      # mod_plists.each {|plist| modified plist}
      # add_plists.each {|plist| added plist}
      # rem_plists.each {|plist| removed plist}
    end # #hear


    # @api private
    #
    # removes changes older than {#keep_minutes} old and plist versions that
    # are no longer referenced.
    #
    # @return nil
    #
    def prune
      info "pruning changes older than #{ @keep_minutes } minutes..."
      limit = Time.now - (60 * @keep_minutes)

      old_file_paths = Set.new
      current_file_paths = Set.new

      Dir["#{ @changes_dir }/*.yml"].each do |path|
        change = YAML.load File.read(path)
        if change['current']['time'] < limit
          debug "deleting change",
            path: path

          # prev may be nil
          change['prev'].maybe {|prev|
            old_file_paths << prev['path']
          }

          FileUtils.rm path
        else
          current_file_paths << change['current']['path']
        end
      end

      to_del = old_file_paths - current_file_paths

      to_del.each do |path|
        debug "removing plist version", path: path
        FileUtils.rm path
      end

      nil
    end # #prune

    # @api private
    #
    # @param system_path [String] absolute path to the plist file.
    #
    # @return nil
    #
    def modified system_path
      debug "processing modified file",
        system_path: system_path

      # do this *before* recording the version so we don't see it as the
      # previous entry when there is no change to go off
      prev_version_path = last system_path
      debug "previous version",
        path: prev_version_path

      # run an update to get the data into the system
      current_version_path = record_version system_path

      # get the data from the previous version
      prev_data = if prev_version_path.nil?
        # if we don't have a previous version, assign nil
        nil
      else
        # otherwise read the previous version
       self.class.read prev_version_path
     end

      # do a diff
      # this will be `nil` if we don't have a previous version
      diff = if prev_data.nil?
        nil
      else
        self.class.diff prev_data, self.class.read(current_version_path)
      end

      # now record a change
      record_change system_path, current_version_path, prev_version_path, diff

      debug "done processing modification.",
        system_path: system_path,
        current_version_path: current_version_path

      nil
    end # #modified

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
  # end private
end
