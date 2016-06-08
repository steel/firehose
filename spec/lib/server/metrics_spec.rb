require 'spec_helper'

describe Firehose::Server::Metrics do
  context "new metrics instance" do
    let(:metrics) { Firehose::Server::Metrics.new }

    describe "#to_hash" do
      it "returns 0 values for the metrics counters" do
        expect(metrics.to_hash).to eql({
          global: {
            active_channels: 0
          },
          channels: {}
        })
      end

      it "returns updated counters" do
        channel  = "/test/channel"
        channel2 = "/test/channel/2"

        3.times { metrics.new_connection! }
        metrics.connection_closed!
        metrics.message_published!(channel)
        2.times { metrics.channel_subscribed!(channel) }
        metrics.channels_subscribed_multiplexed!([channel, channel2])

        expect(metrics.to_hash).to eql({
          global: {
            active_channels: 2,
            connections: 2,
            connections_opened: 3,
            connections_closed: 1,
            published: 1,
            subscribed: 2,
            subscribed_multiplexed: 2
          },
          channels: {
            channel => {
              published: 1,
              subscribed: 2,
              subscribed_multiplexed: 1
            },
            channel2 => {
              subscribed_multiplexed: 1
            }
          }
        })
      end
    end
  end
end
