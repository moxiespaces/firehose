module Firehose
  module Rack
    # Acts as the glue between the HTTP/WebSocket world and the Firehose::Server class,
    # which talks directly to the Redis server. Also dispatches between HTTP and WebSocket
    # transport handlers depending on the clients' request.
    class App
      include Firehose::Rack::Helpers
      attr_reader :session_factory

      def initialize
        yield self if block_given?

        @session_factory = Firehose::Security::SessionFactory.new
      end

      def call(env)
        # Cache the parsed request so we don't need to re-parse it when we pass
        # control onto another app.
        req     = env['parsed_request'] ||= ::Rack::Request.new(env)
        method  = req.request_method

        if session_factory.establish_session(env)
          case method
          when 'PUT'
            # Firehose::Client::Publisher PUT's payloads to the server.
            publisher.call(env)
          when 'HEAD' 
            # HEAD requests are used to prevent sockets from timing out
            # from inactivity
            ping.call(env)
          else
            # ELB doesn't support HEAD requests
            if env['PANTH_INFO'] == '/ping'
              ping.call(env)
            else
              # TODO - 'harden' this up with a GET request and throw a "Bad Request" 
              # HTTP error code. I'd do it now but I'm in a plane and can't think of it.
              consumer.call(env, session_factory)
            end
          end
        else
          response(403, "Invalid user session.")
        end
      end

      # The consumer pulls messages off of the backend and passes messages to the 
      # connected HTTP or WebSocket client. This can be configured from the initialization
      # method of the rack app.
      def consumer
        @consumer ||= Consumer.new
      end

      private
      def publisher
        @publisher ||= Publisher.new
      end

      def ping
        @ping ||= Ping.new
      end
    end
  end
end