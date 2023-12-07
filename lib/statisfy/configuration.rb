module Statisfy
  class Configuration
    attr_accessor :redis_client, :append_to_counters, :default_async_method, :counters_path

    def initialize
      @default_async_method = :perform_async
    end
  end
end
