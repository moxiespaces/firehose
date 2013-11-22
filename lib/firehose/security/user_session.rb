module Firehose
  module Security
    class UserSession
      SESSION_KEY = 'firehose.security.user_session'

      def self.session_data(request)
        user_id = request['user_id']
        superuser = request['superuser']
        if user_id
          [user_id, superuser]
        end
      end

      def self.load(env)
        env[SESSION_KEY]
      end

      attr_reader :user_id, :superuser, :selector

      def initialize(request, user_id, superuser=false)
        env = request.env
        env[SESSION_KEY] = self
        @user_id = user_id
        @superuser = superuser
        @superuser = nil if superuser == ''
        @superuser = false if superuser == 'false'
        @selector = Selector.new(request['selector'])
      end

      def valid_for_session(message_str, message=nil)
        message ||= JSON.parse(message_str)
        if selector.for_message?(message)
          if user_ids = message.delete('user_ids')
            if superuser || (user_id && user_ids.include?(user_id))
              message.to_json
            end
          else
            message_str
          end
        end
      end

      def session_data
        if user_id
          [user_id, superuser]
        end
      end

      private

      def parse_selector(selector)
        unless selector.nil? || selector.blank?
          Selector.new(selector)
        end
      end
    end
  end
end