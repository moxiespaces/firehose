require 'json'

module Firehose
  module Rack
    class Consumer
      class HttpLongPoll
        include Firehose::Rack::Helpers

        # How long should we wait before closing out the consuming clients web connection
        # for long polling? Most browsers timeout after a connection has been idle for 30s.
        TIMEOUT = 20

        # Configures the timeout for the 
        attr_accessor :timeout

        def initialize(timeout=TIMEOUT)
          @timeout = timeout
          yield self if block_given?
        end

        def call(env, session_factory)
          req     = env['parsed_request'] ||= ::Rack::Request.new(env)
          path    = req.path
          method  = req.request_method
          # Get the Last Message Sequence from the query string.
          # Ideally we'd use an HTTP header, but android devices don't let us
          # set any HTTP headers for CORS requests.
          last_sequence = req.params['last_message_sequence'].to_i

          case method
          # GET is how clients subscribe to the queue. When a messages comes in, we flush out a response,
          # close down the requeust, and the client then reconnects.
          when 'GET'
            Firehose.logger.debug "HTTP GET with last_sequence #{last_sequence} for path #{path} with query #{env["QUERY_STRING"].inspect} and params #{req.params.inspect}"
            EM.next_tick do

              user_session = Firehose::Security::UserSession.load(env)
              if last_sequence < 0
                env['async.callback'].call response(400, "The last_message_sequence parameter may not be less than zero", response_headers(req, session_factory, user_session))
              else
                Server::Channel.new(path, user_session).next_message(last_sequence, :timeout => timeout).callback do |message, sequence|
                  env['async.callback'].call response(200, wrap_frame(message, sequence), response_headers(req, session_factory, user_session))
                end.errback do |e|
                  if e == :timeout
                    env['async.callback'].call response(204, '', response_headers(req, session_factory, user_session))
                  else
                    Firehose.logger.error "Unexpected error when trying to GET last_sequence #{last_sequence} for path #{path}: #{e.inspect}"
                    env['async.callback'].call response(500, 'Unexpected error', response_headers(req, session_factory, user_session))
                  end
                end
              end

            end

            # Tell the web server that this will be an async response.
            ASYNC_RESPONSE

          else
            Firehose.logger.debug "HTTP #{method} not supported"
            response(501, "#{method} not supported.")
          end
        end


        private

        def wrap_frame(message, last_sequence)
          JSON.generate :message => message, :last_sequence => last_sequence
        end

        # If the request is a CORS request, return those headers, otherwise don't worry 'bout it
        def response_headers(req, session_factory, user_session)
          headers = cors_origin(req.env) ? cors_headers(req.env) : {}
          # session_factory.apply_cookie(req, headers, user_session)
        end

        def cors_origin(env)
          env['HTTP_ORIGIN']
        end

        def cors_headers(env)
          # TODO seperate out CORS logic as an async middleware with a Goliath web server.
          {
            'Access-Control-Allow-Origin' => cors_origin(env),
            'Access-Control-Allow-Credentials' => true
          }
        end
      end
    end
  end
end