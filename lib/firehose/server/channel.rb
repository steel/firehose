module Firehose
  module Server
    # Connects to a specific channel on Redis and listens for messages to notify subscribers.
    class Channel
      attr_reader :channel_key, :list_key, :sequence_key
      attr_reader :redis, :subscriber

      def self.redis
        @redis ||= EM::Hiredis.connect
      end

      def self.subscriber
        @subscriber ||= Server::Subscriber.new(EM::Hiredis.connect)
      end

      def initialize(channel_key, redis=self.class.redis, subscriber=self.class.subscriber)
        @redis        = redis
        @subscriber   = subscriber
        @channel_key  = channel_key
        @list_key     = Server.key(channel_key, :list)
        @sequence_key = Server.key(channel_key, :sequence)
      end

      def next_messages(consumer_sequence=nil, options={})
        deferrable = EM::DefaultDeferrable.new
        # TODO - Think this through a little harder... maybe some tests ol buddy!
        deferrable.errback {|e| EM.next_tick { raise e } unless [:timeout, :disconnect].include?(e) }

        redis.multi
          redis.get(sequence_key).
            errback {|e| deferrable.fail e }
          # Fetch entire list: http://stackoverflow.com/questions/10703019/redis-fetch-all-value-of-list-without-iteration-and-without-popping
          redis.lrange(list_key, 0, -1).
            errback {|e| deferrable.fail e }
        redis.exec.callback do |(channel_sequence, message_list)|
          # Reverse the messages so they can be correctly procesed by the MessageBuffer class. There's
          # a patch in the message-buffer-redis branch that moves this concern into the Publisher LUA
          # script. We kept it out of this for now because it represents a deployment risk and `reverse!`
          # is a cheap operation in Ruby.
          message_list.reverse!
          buffer = MessageBuffer.new(message_list, channel_sequence, consumer_sequence)
          if buffer.remaining_messages.empty?
            Firehose.logger.debug "No messages in buffer, subscribing. sequence: `#{channel_sequence}` consumer_sequence: #{consumer_sequence}"
            # Either this resource has never been seen before or we are all caught up.
            # Subscribe and hope something gets published to this end-point.
            subscribe(deferrable, options[:timeout])
          else # Either the client is under water or caught up to head.
            deferrable.succeed buffer.remaining_messages
          end
        end.errback {|e| deferrable.fail e }

        deferrable
      end

      def unsubscribe(deferrable)
        subscriber.unsubscribe channel_key, deferrable
      end

      private
      def subscribe(deferrable, timeout=nil)
        subscriber.subscribe(channel_key, deferrable)
        if timeout
          timer = EventMachine::Timer.new(timeout) do
            deferrable.fail :timeout
            unsubscribe deferrable
          end
          # Cancel the timer if when the deferrable succeeds
          deferrable.callback { timer.cancel }
        end
      end
    end
  end
end
