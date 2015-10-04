require 'pathname'
require 'pp'
require 'sinatra/base'

class Plistener
  module UI
    # Our simple hello-world app
    class App < Sinatra::Base
      def initialize working_dir
        @working_dir = Pathname.new working_dir
        super
      end

      def erbetter tpl
        erb tpl, layout: :layout
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
        @changes = Dir[@working_dir + "changes/*.yml"].map do |filepath|
          YAML.load File.read(filepath)
        end

        erbetter :changes
      end

      get '/version/*' do
        p, _, @file_hash = params['splat'].first.rpartition '/'
        @system_path = "/" + p
        @path = @working_dir + "data#{ @system_path }/#{ @file_hash }.yml"
        @contents = File.read(@path)
        @data = YAML.load @contents
        @leaves = Plistener::UI.leaves @data
        @seen = Plistener::UI.seen @working_dir, @system_path, @file_hash

        erbetter :version
      end

      get '/file/*' do
        @system_path = "/" + params['splat'].first
        @history_path = @working_dir + "data#{ @system_path }/history.yml"
        @history = YAML.load @history_path.read

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

      def seen working_dir, system_path, file_hash
        contents = File.read File.join(working_dir.to_s, "data", system_path, "history.yml")
        data = YAML.load contents
        data.select { |entry|
          entry['file_hash'] == file_hash
        }.map {|entry|
          entry['time']
        }
      end

    end # class << self
  end # UI
end # Plistener

# get '/' do
#   "hey"
# end

# class Plistener
#   module UI
#     class << self
#       def run working_dir
#         require 'sinatra'

#         get "/" do
#           "hey"
#         end
#       end
#     end
#   end
# end