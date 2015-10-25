require 'pathname'
require 'pp'
require 'sinatra/base'
require 'nrser/extras'
require 'webrick'
require 'tilt/erubis'

class Plistener
  module UI
    include Plistener::Logger::Include
    configure_logger level: :debug

    # Our simple hello-world app
    class App < Sinatra::Base
      include Plistener::Logger::Include
      configure_logger level: :debug

      def initialize working_dir
        @working_dir = Pathname.new working_dir
        @plnr = Plistener.new @working_dir.to_s
        super
      end

      def erbetter tpl
        erb tpl, layout: :layout
      end

      def partial name, locals
        erb "_#{ name }".to_sym, locals: locals
      end

      # threaded - False: Will take requests on the reactor thread
      #            True:  Will queue request for background thread
      configure do
        set :threaded, false
        set :root, NRSER.git_root(__FILE__) + 'ui'
        set :erb, :escape_html => true
      end

      # shitty error
      get '/favicon.ico' do
        status 404
      end

      # Request runs on the reactor thread (with threaded set to false)
      get '/' do
        @changes = @plnr.changes

        erbetter :changes
      end

      get '/version/*' do
        @system_path, _, time_iso8601 = params['splat'].first.rpartition '@'
        @time = Time.parse(time_iso8601)
        @path = @plnr.version_path @time, @system_path

        @data = Plistener.read @path
        @leaves = Plistener::UI.leaves @data

        erbetter :version
      end

      get '/file/*' do
        @system_path = "/" + params['splat'].first
        @changes = @plnr.changes.select {|change|
          change['path'] == @system_path
        }

        erbetter :file
      end
    end

    class << self

      def run working_dir, options = {}
        port = '7584'
        
        options = {
          log_to_file: false,
        }.merge options
        
        dispatch = Rack::Builder.app do
          map '/' do
            run App.new(working_dir)
          end
        end
        
        server_options = {
          app:    dispatch,
          server: 'webrick',
          Host:   '0.0.0.0',
          Port:   port, # plui
          signals: false,
        }
        
        if options[:log_to_file]        
          log_path = Pathname.new(working_dir) + 'log' + 'ui.log'
          FileUtils.mkdir_p log_path.dirname
          log_file = File.open log_path, 'w'
          log_file.sync = true
          
          server_options[:Logger] = WEBrick::Log.new(log_file)
          server_options[:AccessLog] = [
            [log_file, WEBrick::AccessLog::COMBINED_LOG_FORMAT]
          ]
        end
        
        info 'starting server', port: port
        Rack::Server.start(server_options)
      end # run

      def leaves hash, array = [], prefix = []
        hash.each do |key, value|
          full_key = prefix.dup << key

          if value.is_a? Hash
            leaves value, array, full_key
          else
            array << [full_key, value]
          end
        end

        return array
      end # leaves

      def type_name value
        case CFPropertyList.guess(value)
        when CFPropertyList::CFString
          'string'
        when CFPropertyList::CFInteger
          'int'
        when CFPropertyList::CFReal
          'float'
        when CFPropertyList::CFDate
          'date'
        when CFPropertyList::CFBoolean
          'bool'
        when CFPropertyList::CFData
          'data'
        when CFPropertyList::CFArray
          'array'
        when CFPropertyList::CFDictionary
          'dict'
        when CFPropertyList::CFUid
          'uid'
        else
          "unknown"
        end
      end # type_name

    end # class << self
  end # UI
end # Plistener
