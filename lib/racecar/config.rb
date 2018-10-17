require "king_konf"

module Racecar
  class Config < KingKonf::Config
    env_prefix :racecar

    desc "A list of Kafka brokers in the cluster that you're consuming from"
    list :brokers, default: ["localhost:9092"]

    desc "A string used to identify the client in logs and metrics"
    string :client_id, default: "racecar"

    desc "How frequently to commit offset positions"
    float :offset_commit_interval, default: 10

    desc "How often to send a heartbeat message to Kafka"
    float :heartbeat_interval, default: 10

    desc "The minimum number of messages in the local consumer queue"
    integer :min_message_queue_size, default: 2000

    desc "Kafka consumer configuration options, separated with '=' -- https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md"
    list :consumer, default: []

    desc "Kafka producer configuration options, separated with '=' -- https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md"
    list :producer, default: []

    # TODO: not needed once there is batch support in rdkafka-ruby
    desc "The maxium number of messages that get consumed within one batch"
    integer :fetch_messages, default: 1000

    # TODO: not needed once there is batch support in rdkafka-ruby
    desc "Automatically store offset of last message provided to application"
    boolean :synchonous_commits, default: false

    desc "How long to pause a partition for if the consumer raises an exception while processing a message -- set to -1 to pause indefinitely"
    float :pause_timeout, default: 10

    desc "When `pause_timeout` and `pause_with_exponential_backoff` are configured, this sets an upper limit on the pause duration"
    float :max_pause_timeout, default: nil

    desc "Whether to exponentially increase the pause timeout on successive errors -- the timeout is doubled each time"
    boolean :pause_with_exponential_backoff, default: false

    desc "The idle timeout after which a consumer is kicked out of the group"
    float :session_timeout, default: 30

    desc "How long to wait when trying to communicate with a Kafka broker"
    float :socket_timeout, default: 30

    desc "How long to allow the Kafka brokers to wait before returning messages"
    float :max_wait_time, default: 1

    desc "The maximum size of message sets returned from a single fetch"
    integer :max_bytes, default: 10485760

    desc "A prefix used when generating consumer group names"
    string :group_id_prefix

    desc "The group id to use for a given group of consumers"
    string :group_id

    desc "A filename that log messages should be written to"
    string :logfile

    desc "The log level for the Racecar logs"
    string :log_level, default: "info"

    desc "The file in which to store the Racecar process' PID when daemonized"
    string :pidfile

    desc "Run the Racecar process in the background as a daemon"
    boolean :daemonize, default: false

    desc "The codec used to compress messages with"
    symbol :producer_compression_codec

    desc "Enable Datadog metrics"
    boolean :datadog_enabled, default: false

    desc "The host running the Datadog agent"
    string :datadog_host

    desc "The port of the Datadog agent"
    integer :datadog_port

    desc "The namespace to use for Datadog metrics"
    string :datadog_namespace

    desc "Tags that should always be set on Datadog metrics"
    list :datadog_tags

    # The error handler must be set directly on the object.
    attr_reader :error_handler

    attr_accessor :subscriptions, :logger

    def initialize(env: ENV)
      super(env: env)
      @error_handler = proc {}
      @subscriptions = []
      @logger = Logger.new(STDOUT)
    end

    def inspect
      self.class.variables
        .map(&:name)
        .map {|key| [key, get(key).inspect].join(" = ") }
        .join("\n")
    end

    def validate!
      if brokers.empty?
        raise ConfigError, "`brokers` must not be empty"
      end

      if socket_timeout <= max_wait_time
        raise ConfigError, "`socket_timeout` must be longer than `max_wait_time`"
      end

      if max_pause_timeout && !pause_with_exponential_backoff?
        raise ConfigError, "`max_pause_timeout` only makes sense when `pause_with_exponential_backoff` is enabled"
      end
    end

    def load_consumer_class(consumer_class)
      self.group_id = consumer_class.group_id || self.group_id

      self.group_id ||= [
        # Configurable and optional prefix:
        group_id_prefix,

        # MyFunnyConsumer => my-funny-consumer
        consumer_class.name.gsub(/[a-z][A-Z]/) {|str| str[0] << "-" << str[1] }.downcase,
      ].compact.join("")

      self.subscriptions = consumer_class.subscriptions
      self.max_wait_time = consumer_class.max_wait_time || self.max_wait_time
      self.pidfile ||= "#{group_id}.pid"
    end

    def on_error(&handler)
      @error_handler = handler
    end

    def rdkafka_consumer
      consumer.map do |param|
        param.split("=", 2).map(&:strip)
      end.to_h
    end

    def rdkafka_producer
      producer.map do |param|
        param.split("=", 2).map(&:strip)
      end.to_h
    end
  end
end
