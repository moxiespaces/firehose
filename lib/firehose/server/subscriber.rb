module Firehose
  module Server
    # Setups a connetion to Redis to listen for new resources...
    class Subscriber
      attr_reader :pubsub

      def initialize(redis)
        @pubsub = redis.pubsub
        # TODO: Instead of just raising an exception, it would probably be better
        #       for the errback to set some sort of 'disconnected' state. Then
        #       whenever a deferrable was 'subscribed' we could instantly fail
        #       the deferrable with whatever connection error we had.
        #       An alternative which would have a similar result would be to
        #       subscribe lazily (i.e. not until we have a deferrable to subscribe).
        #       Then, if connecting failed, it'd be super easy to fail the deferrable
        #       with the same error.
        #       The final goal is to allow the failed deferrable bubble back up
        #       so we can send back a nice, clean 500 error to the client.
        channel_updates_key = Server.key('channel_updates')
        pubsub.subscribe(channel_updates_key).
          errback{|e| EM.next_tick { raise e } }.
          callback { Firehose.logger.debug "Redis subscribed to `#{channel_updates_key}`" }
        pubsub.on(:message) do |_, payload|
          channel_key, sequence, message = Server::Publisher.from_payload(payload)

          if deferrables = subscriptions.delete(channel_key)
            Firehose.logger.debug "Redis notifying #{deferrables.count} deferrable(s) at `#{channel_key}` with sequence `#{sequence}` and message `#{message}`"
            deferrables.each do |hash|
              deferrable = hash[:deferrable]
              user_session = hash[:user_session]
              if message = user_session.secure_for_message(message)
                Firehose.logger.debug "Sending message #{message} and sequence #{sequence} to client from subscriber"
                deferrable.succeed message, sequence.to_i
              else
                Firehose.logger.debug "Skipping message #{message} and sequence #{sequence} for user: #{user_session.user_id}"
                subscribe(channel_key, deferrable, user_session)
              end
            end
            subscriptions.delete(channel_key) if subscriptions[channel_key].empty?
          end
        end
      end

      def subscribe(channel_key, deferrable, user_session)
        subscriptions[channel_key].push :deferrable => deferrable, :user_session => user_session
      end

      def unsubscribe(channel_key, deferrable)
        hash = subscriptions[channel_key].detect {|h| h[:deferrable] == deferrable}
        subscriptions[channel_key].delete(hash) if hash
        subscriptions.delete(channel_key) if subscriptions[channel_key].empty?
      end

      private
      def subscriptions
        @subscriptions ||= Hash.new{|h,k| h[k] = []}
      end
    end
  end
end