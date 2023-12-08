module Statisfy
  module Monthly
    def self.included(klass)
      klass.extend(ClassMethods)
    end

    module ClassMethods
      #
      # Returns a hash of values grouped by month:
      # {
      #   "01/2024" => 33.3,
      #   "02/2024" => 36.6,
      #   "03/2024" => 38.2,
      # }
      #
      # @param scope: the scope of the counter (an Organisation or a Department)
      # @param start_at: the date from which you want to start counting (optional)
      # @param stop_at: the date at which you want to stop counting (optional)
      #
      def values_grouped_by_month(scope: nil, start_at: nil, stop_at: nil)
        n_months = 24

        if start_at.present? || scope&.created_at.present?
          start_at ||= scope.created_at
          n_months = (Time.zone.today.year + Time.zone.today.month) - (start_at.year + start_at.month)
        end

        relevant_months = (0..n_months).map do |i|
          (n_months - i).months.ago.beginning_of_month
        end

        relevant_months
          .filter { |month| stop_at.blank? || month < stop_at }
          .to_h do |month|
          [month.strftime("%m/%Y"), value(scope:, month:).round(2)]
        end
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
