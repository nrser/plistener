require 'logger'
require 'pastel'

require 'nrser'
require 'nrser/refinements'

using NRSER

class Plistener
  class Logger
    LEVEL_NAMES = [
      :debug,
      :info,
      :warn,
      :error,
      :fatal,
      :unknown,
    ]

    SEVERITY_COLORS = {
      'DEBUG' => :bright_black,
      'WARN' => :yellow,
      'INFO' => :green,
      'ERROR' => :red,
      'FATAL' => :on_red,
    }

    @@pastel = Pastel.new

    module Include
      module ClassMethods
        def logger
          class_variable_get :@@__logger
        end

        def debug *args
          logger.debug *args
        end

        def info *args
          logger.info *args
        end

        def warn *args
          logger.warn *args
        end

        def error *args
          logger.error *args
        end

        def fatal *args
          logger.fatal *args
        end

        def configure_logger options = {}
          options[:name] ||= self.name
          class_variable_set :@@__logger, Plistener::Logger.new(options)
        end
      end # ClassMethods

      def debug *args
        self.class.debug *args
      end

      def info *args
        self.class.info *args
      end

      def warn *args
        self.class.warn *args
      end

      def error *args
        self.class.error *args
      end

      def fatal *args
        self.class.fatal *args
      end

      def self.included base
        base.extend ClassMethods
      end
    end # Include

    # class functions
    # ==============

    # @api util
    # *pure*
    #
    # format a debug message with optional key / values to print
    #
    # @param msg [String] message to print.
    # @param dump [Hash] optional hash of keys and vaues to dump.
    def self.format msg, dump = {}
      unless dump.empty?
        msg += "\n" + dump.map {|k, v| "  #{ k }: #{ v.inspect }" }.join("\n")
      end
      msg
    end

    def initialize options = {}
      @options = {
        dest: $stdout,
        level: ::Logger::INFO,
        say_hi: true,
      }.merge options

      @logger = ::Logger.new @options[:dest]
      @logger.level = @options[:level]

      @logger.formatter = proc do |severity, datetime, progname, msg|
        prefix = "[#{ progname } #{ severity }]"
        padding = " " * (prefix.length + 1)

        if SEVERITY_COLORS[severity]
          prefix = @@pastel.method(SEVERITY_COLORS[severity]).call prefix
        end

        prefix = prefix + " "

        lines = msg.split "\n"
        new_lines = [prefix + lines.first]
        lines[1..-1].each do |line|
          new_lines << (padding + line)
        end
        new_lines.join("\n") + "\n"
      end

      if @options[:say_hi]
        info NRSER.squish <<-END
          started to logging to #{ @options[:dest] } at level
          #{ LEVEL_NAMES[@options[:level]].to_s.upcase }...
        END
      end
    end

    def debug msg, dump = {}
      send_log :debug, msg, dump
    end

    def info msg, dump = {}
      send_log :info, msg, dump
    end

    def warn msg, dump = {}
      send_log :warn, msg, dump
    end

    def error msg, dump = {}
      send_log :error, msg, dump
    end

    def fatal msg, dump = {}
      send_log :fatal, msg, dump
    end

    private
      def send_log level_name, msg, dump
        @logger.send(level_name, @options[:name]) {
          Plistener::Logger.format(msg, dump)
        }
      end
    # end private

  end # Logger
end # Plistener
