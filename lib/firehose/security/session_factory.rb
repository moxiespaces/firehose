require 'ezsig'
require 'cgi'
module Firehose
  module Security
    class SessionFactory
      attr_reader :signer, :verifier

      def initialize
        key_file = File.expand_path('../../../../config/key', __FILE__)
        @signer = EzCrypto::Signer.from_file(key_file)
        @verifier = signer.verifier
      end

      def establish_session(env)
        request = env['parsed_request'] ||= ::Rack::Request.new(env)
        
        if data = UserSession.session_data(request)
          ttl = request.params['ttl']
          signature = request.params['signature']

          if ttl && signature && ttl.to_i > 0 && Time.at(ttl.to_i) >= Time.now && verify(*data, ttl, signature)
            env['FIREHOSE_COOKIE'] = true
            UserSession.new(env, *data)
          end
        elsif cookie = request.cookies['_firehose']
          data = cookie.split(':')
          signature = data.pop
          remote_addr = data.pop
          if request.ip == remote_addr && verify(*data, remote_addr, signature)
            UserSession.new(env, *data)
          end
        else
          UserSession.new(env, nil)
        end
      end

      def verify(*data, signature)
        string = data.join(":")
        signature = Base64.decode64(signature)
        verifier.verify(signature, string)
      end

      def apply_cookie(request, headers, user_session)
        return headers unless request.env['FIREHOSE_COOKIE']
        data = user_session.session_data
        return headers unless data

        remote_address = request.ip
        data = "#{data.join(':')}:#{remote_address}"
        signature = Base64.encode64(signer.sign(data))
        ::Rack::Utils.set_cookie_header!(
          headers,
          '_firehose',
          :value => "#{data}:#{signature}",
          :path => '/',
          :httponly => true,
          :domain => request.host
        )

        headers
      end
    end
  end
end