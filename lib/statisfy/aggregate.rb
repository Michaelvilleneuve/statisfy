require_relative "counter"

module Statisfy
  module Aggregate
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.class_eval do
        include Counter
      end
    end

    module ClassMethods
      #
      # Simply a shortcut for declaring an aggregation type counter
      #
      def aggregate(args = {})
        raise ArgumentError, "You must provide the value to aggregate" if args[:value].blank?

        count(args.merge(type: :aggregate))
      end

      #
      # Average type counters ret
      #
      # @param scope: the scope of the counter (an Organisation or a Department)
      # @param month: the month for which you want the value of the counter (optional)
      #
      def value(scope: nil, month: nil)
        p "HEIN???"
        month = month&.strftime("%Y-%m") if month.present?
        average(scope:, month:)
      end
    end
  end
end
