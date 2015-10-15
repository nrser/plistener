class Plistener
  module Error
    # base class for Plistener-specific errors
    class PlistenerError < StandardError; end

    # raised when parsing a plist file fails
    class ParseError < PlistenerError; end

    # raised when there is a problem with the config file
    class ConfigError < PlistenerError; end

    # raised when a file was reported as changed but no previous
    # version was found in the data directory
    class PreviousVersionNotFoundError < PlistenerError; end

    class ChangePathConflictError < PlistenerError
      def initialize change_path
        msg = binding.erb <<-END
          change path <%= change_path %> already exists. this is not
          expected - change paths incorporate millisecond time, so something
          must have happen *much* faster than we expect or there is a logic
          error.
        END
      end
    end
  end
end
