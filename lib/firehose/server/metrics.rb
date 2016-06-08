require "set"

module Firehose::Server
  class Metrics
    def initialize
      @active_channels = Set.new
      @global = Hash.new { 0 }
      @channel_metrics = Hash.new
    end

    # metric handlers

    def message_published!(channel)
      @active_channels << channel
      incr_global! :published
      incr_channel! channel, :published
    end

    def channel_subscribed!(channel)
      @active_channels << channel
      incr_global! :subscribed
      incr_channel! channel, :subscribed
    end

    def channels_subscribed_multiplexed!(channels)
      channels.each do |channel|
        @active_channels << channel
        incr_global! :subscribed_multiplexed
        incr_channel! channel, :subscribed_multiplexed
      end
    end

    def new_connection!
      incr_global! :connections
      incr_global! :connections_opened
    end

    def connection_closed!
      incr_global! :connections_closed
      decr_global! :connections
    end

    # serialization helpers (used to store metrics to redis)

    def to_hash
      {
        global: @global.merge(active_channels: @active_channels.size),
        channels: @channel_metrics
      }
    end

    def to_json
      JSON.generate self.to_hash
    end

    private

    def incr_global!(name, increment = 1)
      @global[name] += increment
    end

    def decr_global!(name, decrement = 1)
      @global[name] -= decrement
    end

    def incr_channel!(channel, counter, increment = 1)
      channel_metrics(channel)[counter] += increment
    end

    def decr_channel!(channel, counter, decrement = 1)
      channel_metrics(channel)[counter] -= decrement
    end

    def channel_metrics(channel)
      @channel_metrics[channel] ||= Hash.new { 0 }
    end
  end
end
