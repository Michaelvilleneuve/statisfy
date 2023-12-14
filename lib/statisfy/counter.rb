require_relative "subscriber"
require_relative "monthly"

module Statisfy
  module Counter
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.class_eval do
        include Subscriber, Monthly
        attr_accessor :params, :subject
      end
    end

    module ClassMethods
      #
      # This is a DSL method that helps you define a counter
      # It will create a method that will be called when the event is triggered
      # It will also create a method that will be called when you want to get the value of the counter
      #
      # @param every: the event(s) that will trigger the counter
      # @param type: by default it increments, but you can also use :average
      # @param if: a block that returns a condition that must be met for the counter to be incremented (optional)
      # @param if_async: same as if option but runs async to avoid slowing down inserts and updates (optional)
      # @param uniq_by: a block to get the identifier of the element to be counted (optional)
      # @param scopes: a block to get the list of scopes for which the counter must be incremented (optional)
      #
      def count(args = {})
        raise ArgumentError, "You must provide at least one event" if args[:every].blank?

        catch_events(*args[:every])
        apply_default_counter_options(args)
        const_set(:COUNTER_TYPE, args[:type] || :increment)
        class_eval(&Statisfy.configuration.append_to_counters) if Statisfy.configuration.append_to_counters.present?
      end

      #
      # This method serves as a syntactic sugar
      # The below methods could be written directly in the class definition
      # but the `count` DSL defines them automatically based on the options provided
      #
      def apply_default_counter_options(args)
        define_method(:identifier, args[:value] || args[:uniq_by] || -> { nil })
        define_method(:scopes, args[:scopes] || Statisfy.configuration.default_scopes || -> { [] })
        define_method(:if_async, args[:if_async] || -> { true })
        define_method(:decrement?, args[:decrement_if] || -> { false })
        define_method(:should_run?, args[:if] || -> { true })
        define_method(:decrement_on_destroy?, -> { args[:decrement_on_destroy] != false })
        define_method(:month_to_set, args[:date_override] || -> { params["created_at"] })
      end

      #
      # This is the method that is called when you want to get the value of a counter.
      #
      # By default it returns the number of elements in the set.
      # You can override it if the counter requires more complex logic
      # see RateOfAutonomousUsers for example
      #
      # @param scope: the scope of the counter (an Organisation or a Department)
      # @param month: the month for which you want the value of the counter (optional)
      #
      def value(scope: nil, month: nil)
        month = month&.strftime("%Y-%m") if month.present?
        if const_get(:COUNTER_TYPE) == :aggregate
          average(scope:, month:)
        else
          size(scope:, month:)
        end
      end

      def aggregate_counter?
        const_get(:COUNTER_TYPE) == :aggregate
      end

      def size(scope: nil, month: nil)
        redis_client.scard(key_for(scope:, month:))
      end

      def members(scope: nil, month: nil)
        redis_client.smembers(key_for(scope:, month:))
      end

      #
      # Returns the list of elements in the set (in case you use .append and not .increment)
      #
      def elements_in(scope: nil, month: nil)
        redis_client.lrange(key_for(scope:, month:), 0, -1)
      end

      def sum(scope: nil, month: nil)
        stored_values = elements_in(scope:, month:)
        return 0 if stored_values.empty?

        stored_values.map(&:to_i).reduce(:+)
      end

      #
      # Returns the average of the elements in the set
      # Example:
      # append(value: 1)
      # append(value: 2)
      # average
      # => 1.5
      #
      def average(scope: nil, month: nil)
        stored_values = elements_in(scope:, month:)
        return 0 if stored_values.empty?

        stored_values.map(&:to_i).reduce(:+) / stored_values.length.to_f
      end

      #
      # This is the name of the Redis key that will be used to store the counter
      #
      def key_for(scope:, month: nil, key_value: nil)
        {
          counter: name.demodulize.underscore,
          month:,
          scope_type: scope&.class&.name,
          scope_id: scope&.id,
          key_value:
        }.to_json
      end

      def redis_client
        Statisfy.configuration.redis_client
      end

      #
      # This allows to run a counter increment manually
      # It is useful when you want to backfill counters
      #
      def trigger_with(resource, options = {})
        counter = new
        counter.params = resource

        return unless options[:skip_validation] || counter.should_run?

        counter.perform(resource)
      end

      #
      # Returns the list of all the keys of this counter for a given scope (optional)
      # and a given month (optional)
      #
      def all_keys(scope: nil, month: nil)
        redis_client.keys("*\"counter\":\"#{name.demodulize.underscore}\"*").filter do |json|
          key = JSON.parse(json)

          scope_matches = scope.nil? || (key["scope_type"] == scope.class.name && key["scope_id"] == scope.id)
          month_matches = month.nil? || key["month"] == month

          scope_matches && month_matches
        end
      end
      # rubocop:enable Metrics/AbcSize

      #
      # This allows to reset all the counters for a given scope (optional)
      # and a given month (optional)
      #
      def reset(scope: nil, month: nil)
        all_keys(scope:, month:).each do |key|
          redis_client.del(key)
        end

        true
      end
    end

    protected

    def scopes_with_global
      scopes.flatten.compact << nil
    end

    def process_event
      return decrement if can_decrement_on_destroy?
      return unless if_async

      if self.class.aggregate_counter?
        append
      else
        decrement? ? decrement : increment
      end
    end

    def can_decrement_on_destroy?
      params[:statisfy_trigger] == :destroy && !self.class.aggregate_counter? && decrement_on_destroy?
    end

    def value
      identifier || params["id"]
    end

    #
    # This allows to iterate over all the counters that need to be updated
    # (in general the Department(s) and Organisation(s) for both the current month and the global counter)
    #
    def all_counters
      [month_to_set.to_date.strftime("%Y-%m"), nil].each do |month|
        scopes_with_global.each do |scope|
          yield self.class.key_for(scope:, month:)
        end
      end
    end

    def increment
      all_counters do |key|
        self.class.redis_client.sadd?(key, value)

        # When setting a uniq_by option, we use this set to keep track of the number of unique instances
        # with the same identifier.
        # When there are no more instances with this identifier, we can decrement the counter
        self.class.redis_client.sadd?(key_for_instance_ids(key), params["id"]) if identifier.present?
      end
    end

    #
    # To be used to store a list of values instead of a basic counter
    #
    def append
      all_counters do |key|
        self.class.redis_client.rpush(key, value)
      end
    end

    # rubocop:disable Metrics/AbcSize
    def decrement
      all_counters do |key|
        if identifier.present?
          self.class.redis_client.srem?(key_for_instance_ids(key), params["id"])
          self.class.redis_client.srem?(key, value) if no_more_instances_with_this_identifier?(key)
        else
          self.class.redis_client.srem?(key, value)
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    def no_more_instances_with_this_identifier?(key)
      self.class.redis_client.scard(key_for_instance_ids(key)).zero?
    end

    #
    # This redis key is used when setting a uniq_by. It stores the list of ids of the main resource (e.g. User)
    # in order to count the number of unique instances with the same identifier
    #
    # When the associated array becomes empty, it means that we can
    # decrement the counter because there are no more instances associated with this identifier
    #
    def key_for_instance_ids(key)
      JSON.parse(key).merge("subject_id" => identifier).to_json
    end
  end
end

# rubocop:enable Metrics/ModuleLength
