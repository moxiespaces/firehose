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

      attr_reader :user_id
      attr_reader :superuser

      def initialize(env, user_id, superuser=false)
        env[SESSION_KEY] = self
        @user_id = user_id
        @superuser = superuser
        @superuser = nil if superuser == ''
      end

      def secure_for_message(message_str)
        message = JSON.parse(message_str)
        if user_ids = message.delete('user_ids')
          if superuser || (user_id && user_ids.include?(user_id))
            message.to_json
          end
        else
          message_str
        end
      end

      def session_data
        if user_id
          [user_id, superuser]
        end
      end
    end
  end
end