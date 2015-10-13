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
          class_variable_get(:@@__logger) || configure_logger
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
          instance = Plistener::Logger.new(options)
          class_variable_set :@@__logger, instance
          instance
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

    def self.int_level level
      case level
      when Fixnum
        level
      when Symbol
        LEVEL_NAMES.each_with_index {|sym, index|
          return index if level == sym
        }
      else
        raise "bad level: #{ level.inspect }"
      end
    end

    def initialize options = {}
      @options = {
        dest: $stdout,
        level: :info,
        say_hi: true,
      }.merge options

      @logger = ::Logger.new @options[:dest]
      @logger.level = self.class.int_level @options[:level]

      @logger.formatter = proc do |severity, datetime, progname, msg|
        prefix = "[#{ progname } #{ severity } #{ datetime.strftime('%Y.%m.%d-%H.%M.%s.%L') }]"
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

    def debug *args
      send_log :debug, args
    end

    def info *args
      send_log :info, args
    end

    def warn *args
      send_log :warn, args
    end

    def error *args
      send_log :error, args
    end

    def fatal *args
      send_log :fatal, args
    end

    private
      def send_log level_name, args
        msg = ''
        dump = {}
        case args.length
        when 1
          case args[0]
          when Hash
            dump = args[0]
          when String
            msg = args[0]
          else
            msg = args[0].to_s
          end
        when 2
          msg, dump = args
        else
          raise "must provide one or two arguments, not #{ args.length }"
        end

        @logger.send(level_name, @options[:name]) {
          Plistener::Logger.format(msg, dump)
        }
      end
    # end private

  end # Logger
end # Plistener
