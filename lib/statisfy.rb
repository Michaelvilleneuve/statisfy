# frozen_string_literal: true

require_relative "statisfy/configuration"
require_relative "statisfy/counter"
require_relative "statisfy/aggregate"
require_relative "statisfy/monthly"

module Statisfy
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
