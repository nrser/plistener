require 'logger'
require 'pastel'

require 'nrser'
require 'nrser/refinements'

using NRSER

class Plistener
  class Logger
    LEVEL_SYMS = [
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
          class_variable_get(:@@__logger)
        end

        def debug *args
          send_log :debug, *args
        end

        def info *args
          send_log :info, *args
        end

        def warn *args
          send_log :warn, *args
        end

        def error *args
          send_log :error, *args
        end

        def fatal *args
          send_log :fatal, *args
        end

        def send_log method_name, *args
          return unless configured?
          logger.send method_name, *args
        end

        def configured?
          class_variable_defined?(:@@__logger)
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

    # @api util
    #
    #
    def self.check_level level
      case level
      when Fixnum
        unless level >= 0 && level < LEVEL_SYMS.length
          raise ArgumentError.new "invalid integer level: #{ level.inspect }"
        end
      when Symbol
        unless LEVEL_SYMS.include? level
          raise ArgumentError.new "invalid level symbol: #{ level.inspect }"
        end
      when String
        unless LEVEL_SYMS.map {|_| _.to_s.upcase}.include? level
          raise ArgumentError.new "invalid level name: #{ level.inspect }"
        end
      else
        raise TypeError.new binding.erb <<-END
          level must be Fixnum, Symbol or String, not <%= level.inspect %>
        END
      end
    end # #check_level

    # @api util
    # *pure*
    #
    # get the integer value of a level (like ::Logger::DEBUG, etc.).
    #
    # @param level [Fixnum, Symbol, String] the integer level, method symbol,
    #     or string name (all caps).
    #
    # @return [Fixnum] level integer (between 0 and 5 inclusive).
    #
    def self.level_int level
      check_level level
      case level
      when Fixnum
        level
      when Symbol
        LEVEL_SYMS.each_with_index {|sym, index|
          return index if level == sym
        }
      when String
        LEVEL_SYMS.each_with_index {|sym, index|
          return index if level == sym.to_s.upcase
        }
      end
    end

    # @api util
    # *pure*
    #
    # get the string "name" of a level ('DEBUG', 'INFO', etc.).
    #
    # @param level [Fixnum, Symbol, String] the integer level, method symbol,
    #     or string name (all caps).
    #
    # @return ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'UNKNOWN']
    #
    def self.level_name level
      check_level level
      case level
      when Fixnum
        LEVEL_SYMS[level].to_s.upcase
      when Symbol
        level.to_s.upcase
      when String
        level
      end
    end

    # @api util
    # *pure*
    #
    # get the symbol for a level as used in method sigs.
    #
    # @param level [Fixnum, Symbol, String] the integer level, method symbol,
    #     or string name (all caps).
    #
    # @return [:debug, :info, :warn, :error, :fatal, :unknown]
    #
    def self.level_sym level
      check_level level
      case level
      when Fixnum
        LEVEL_SYMS[level]
      when Symbol
        level
      when String
        level.downcase.to_sym
      end
    end

    attr_reader :name, :dest, :level

    def initialize options = {}
      options = {
        dest: $stdout,
        level: :info,
        say_hi: true,
        on: true,
      }.merge options

      @name = options[:name]
      @on = options[:on]
      @dest = options[:dest]
      @level = options[:level]

      @logger = ::Logger.new @dest
      @logger.level = self.class.level_int @level

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

      if @on && options[:say_hi]
        info NRSER.squish <<-END
          started to logging to #{ @dest } at level
          #{ self.class.level_name @level }...
        END
      end
    end

    def on?
      @on
    end

    def off?
      !on?
    end

    def on &block
      if block
        prev = @on
        @on = true
        block.call
        @on = prev
      else
        @on = true
      end
    end

    def off &block
      if block
        prev = @on
        @on = false
        block.call
        @on = prev
      else
        @on = false
      end
    end

    def level= level
      @logger.level = @level = level
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
        return unless @on

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

        @logger.send(level_name, @name) {
          Plistener::Logger.format(msg, dump)
        }
      end
    # end private

  end # Logger
end # Plistener
