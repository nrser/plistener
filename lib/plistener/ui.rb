require 'pathname'
require 'pp'
require 'sinatra/base'

class Plistener
  module UI
    include Plistener::Logger::Include

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
        set :root, (Pathname.new(__FILE__).dirname + ".." + ".." + "ui")
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

      def run working_dir
        dispatch = Rack::Builder.app do
          map '/' do
            run App.new(working_dir)
          end
        end

        Rack::Server.start({
          app:    dispatch,
          # server: 'thin',
          Host:   '0.0.0.0',
          Port:   '7584', # plui
          signals: false,
        })
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
