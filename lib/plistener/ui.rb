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
        set :root, (Pathname.new(__FILE__).dirname + "ui")
      end

      # Request runs on the reactor thread (with threaded set to false)
      get '/' do
        @changes = Dir[@working_dir + "changes/*.yml"].map do |filepath|
          YAML.load File.read(filepath)
        end

        erbetter :changes
      end

      get '/version/*' do
        @path = @working_dir + "data/#{ params['splat'].first }.yml"
        @contents = File.read(@path)
        @data = YAML.load @contents
        @leaves = Plistener::UI.leaves @data

        # case params['view']
        # when 'yaml'
        #   erbetter :version_yaml
        # else
          erbetter :version
        # end
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
          Port:   '8181',
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