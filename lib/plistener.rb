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

require 'plistener/version'
require 'plistener/logger'
require 'plistener/error'

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

  # constants
  # =========

  DEFAULT_PATHS = [ '~/Library/Preferences', '/Library/Preferences', ]
  DEFAULT_KEEP_MINUTES = 15

  # attributes
  # ==========

  attr_accessor :paths,
                :config_path,
                :keep_minutes,
                :listening,
                :changes_dir,
                :data_dir,
                :paths

  # class configuration
  # ==================

  include Plistener::Logger::Include
  # configure_logger level: ::Logger::DEBUG

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
    # return {} if File.zero? plist_path
    begin
      StateMate::Adapters::Defaults.read [plist_path]
    rescue Exception => e
      raise Error::ParseError.new binding.erb <<-END
        error reading plist at <%= plist_path %>:

        e.format
      END
    end
  end # .read


  # @api util
  # *pure*
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
  #     'modify' elements have 'from' and 'to' keys mapped to the old
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
          'op' => 'modify',
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


  # public API instance methods
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

  # @api public
  #
  #
  def changes system_path = nil
    Dir.glob("#{ @changes_dir }/*.yml").map {|path|
      YAML.load File.open(path)
    }
  end

  # util instance methods
  # =====================

  # @api util
  #
  def versions_dir plist_system_path
    File.join @data_dir, plist_system_path
  end # #versions_dir


  # @api util
  #
  # get the path to a version of the plist in the data folder.
  #
  # @param time [Time] the time to base the version on.
  # @param plist_system_path [String] absolute path to the plist on the system.
  #
  # @return [String] the absolute path to the version in the `data` dir.
  #
  def version_path time, plist_system_path
    "#{ versions_dir(plist_system_path) }/#{ self.class.time_str time }_#{ File.basename plist_system_path }"
  end


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

  # private

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
      version_path = version_path time, system_path

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
    # a 'change' looks like:
    #
    #     {
    #       'path' => String,
    #       'type' => 'modify' | 'add' | 'remove',
    #       'time' => Time,
    #       'prev' => nil | {
    #         'path' => String,
    #         'time' => Time
    #       },
    #       'current' => nil | {
    #         'path' => String,
    #         'time' => Time,
    #       },
    #       'diff' => [
    #         nil | {
    #           'op' => 'update',
    #           'key' => String,
    #           'from' => Object,
    #           'to' => Object,
    #         } | {
    #           'op' => 'add',
    #           'key' => String,
    #           'added' => Object,
    #         } | {
    #           'op' => 'remove',
    #           'key' => String,
    #           'removed' => Object,
    #         }
    #       ]
    #     }
    #
    # @param system_path [String] absolute path to plist on system.
    #
    # @param current_version_path [String, nil] absolute path to the current
    #     version in the `data` folder. will be `nil` in the case of a removed
    #     file.
    #
    # @param prev_version_path [String, nil] absolute path to the previous
    #     version in the `data` folder. will be `nil` in the case of added
    #     files and changes for which we can't find a previous version.
    #
    # @param diff [Array<Hash<String, Object>>, nil] the output of {#diff}.
    #     may be `nil` if we don't have a previous version to diff against.
    #
    # @return nil
    #
    def record_change system_path,
                      type,
                      current_version_path,
                      prev_version_path,
                      diff
      now = Time.now
      change_path = change_path now, system_path

      raise ChangePathConflictError.new if File.exists? change_path

      change = {
        'path' => system_path,
        'type' => type,
        'time' => now,
        'prev' => nil,
        'current' => nil,
        'diff' => diff,
      }

      # add data for the previous and current versions of the file
      # if we received paths for them.
      {
        'current' => current_version_path,
        'prev' => prev_version_path,
      }.each do |key, path|
        unless path.nil?
          change[key] = {
            'path' => path,
            'time' => File.mtime(path),
          }
        end
      end

      File.open(change_path, 'w') do |f|
        f.write YAML.dump(change)
      end

      nil
    end # #record_change


    # @api private
    #
    # record that an error happen when processing a file change.
    #
    # @param system_path [String] absolute path to plist file on system.
    # @param type ['modified', 'added', 'removed'] the type of file change.
    # @param error [Exception] the error that occured.
    #
    # @return nil
    #
    def record_error system_path, type, error
      change_path = change_path Time.now, system_path

      raise ChangePathConflictError.new if File.exists? change_path

      change = {
        'path' => system_path,
        'type' => type,
        'error' => error.format,
      }

      File.open(change_path, 'w') do |f|
        f.write YAML.dump(change)
      end

      nil
    end


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
          record_error system_path, type, error
        end
      }

      add_plists = add_paths.map {|path|
        info "file added", path: path
        begin
          added system_path
        rescue Exception => e
          record_error system_path, type, error
        end
      }

      rem_plists = rem_paths.map {|path|
        info "file removed", path: path
        begin
          removed system_path
        rescue Exception => e
          record_error system_path, type, error
        end
      }
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

      # if the previous version path is `nil` raise an error, which will
      # get recorded by the caller
      raise Error::PreviousVersionNotFoundError if prev_version_path.nil?

      debug "previous version",
        path: prev_version_path

      # record this version, getting the path to it in the data dir
      current_version_path = record_version system_path

      # get the data from the previous version
      prev_data = self.class.read prev_version_path

      # do a diff
      diff = self.class.diff  self.class.read(prev_version_path),
                              self.class.read(current_version_path)

      # now record a change
      record_change system_path,
                    'modified',
                    current_version_path,
                    prev_version_path,
                    diff

      debug "done processing modification.",
        system_path: system_path,
        current_version_path: current_version_path

      nil
    end # #modified

    # @api private
    def added system_path
      debug "processing added file",
        system_path: system_path

      version_path = record_version system_path
      diff = self.class.diff({}, self.class.read(version_path))
      record_change system_path, 'added', version_path, nil, diff
    end

    def removed system_path
      debug "processing removed file",
        system_path: system_path

      # get the path to the previous version (may be `nil`)
      prev_version_path = last system_path

      # if that path is `nil` raise an error, which will get recorded
      # by the caller
      raise Error::PreviousVersionNotFoundError if prev_version_path.nil?

      diff = self.class.diff self.class.read(prev_version_path), {}
      record_change system_path, 'removed', nil, prev_version_path, diff
    end
  # end private
end
