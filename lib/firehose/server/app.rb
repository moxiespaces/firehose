module Firehose
  module Server
    # Configure servers that are booted with-out going through Rack. This is mostly used by
    # the `firehose server` CLI command or for testing. Production configurations are likely
    # to boot with custom rack configurations.
    class App
      def initialize(opts={})
        @port   = opts[:port]   || Firehose::URI.port
        @host   = opts[:host]   || Firehose::URI.host
        @server = opts[:server] || :rainbows

        Firehose.logger.info "Starting #{Firehose::VERSION} '#{Firehose::CODENAME}', in #{ENV['RACK_ENV']}"
      end

      def start
        self.send("start_#{@server}")
      end

      private
      # Boot the Firehose server with the Rainbows app server.
      def start_rainbows
        require 'rainbows'
        Faye::WebSocket.load_adapter('rainbows')

        rackup = Unicorn::Configurator::RACKUP
        rackup[:port] = @port if @port
        rackup[:host] = @host if @host
        rackup[:set_listener] = true
        opts = rackup[:options]
        opts[:config_file] = File.expand_path('../../../../config/rainbows.rb', __FILE__)

        server = Rainbows::HttpServer.new(new_app_with_cors, opts)
        server.start.join
      end

      # Boot the Firehose server with the Thin app server.
      def start_thin
        require 'thin'

        Faye::WebSocket.load_adapter('thin')

        # TODO: See if we can just set Thin to use Firehose.logger instead of
        #       printing out messages by itself.
        Thin::Logging.silent = true if Firehose.logger.level == Logger::ERROR

        app = new_app_with_cors
        server = Thin::Server.new(@host, @port) do
          run app
        end.start
      end

      # Create a new FirehoseApp wrapped with cors support
      def new_app_with_cors
        require 'rack/cors'
        app = Firehose::Rack::App.new
        ::Rack::Cors.new(app) do
          allow do
            origins 'https://*.moxiesoft.com',
                    'https://*.moxiespaces.com',
                    'https://*.moxiedev.com',
                    'http://*.ngenplatform.com'

            resource '*',
              :methods => :get,
              :headers => :any
          end
        end
      end
    end
  end
end