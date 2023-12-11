require "ostruct"

module Statisfy
  module Model
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.class_eval do
        @statisfy = {}
      end
    end

    module ClassMethods
      def count(params)
        raise ArgumentError, "Missing :as parameter" unless params[:as]

        class_name = params[:as].to_s.camelize

        eval <<-RUBY, binding, __FILE__, __LINE__ + 1
          class ::Statisfy::#{class_name}
            include Statisfy::#{params[:type] == :aggregate ? "Aggregate" : "Counter"}
          end
        RUBY

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def self.#{params[:as]}
            ::Statisfy::#{class_name}
          end
        RUBY

        "::Statisfy::#{class_name}".constantize.send(__method__, **params)
      end

      def aggregate(params)
        count(params.merge(type: :aggregate))
      end
    end
  end
end
