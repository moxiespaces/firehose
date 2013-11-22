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

        case method
        when 'PUT'
          session_protect(env) do
            # Firehose::Client::Publisher PUT's payloads to the server.
            publisher.call(env)
          end
        when 'HEAD' 
          # HEAD requests are used to prevent sockets from timing out
          # from inactivity
          ping.call(env)
        when 'GET'
          # ELB doesn't support HEAD requests
          if env['PATH_INFO'] == '/ping'
            ping.call(env)
          else
            session_protect(env) do
              consumer.call(env, session_factory)
            end
          end
        else
          response(405, "", :Allow => 'GET, HEAD, PUT')
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

      def session_protect(env, &block)
        if session_factory.establish_session(env)
          yield block
        else
          response(403, "Invalid user session.")
        end
      end
    end
  end
end