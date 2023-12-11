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
        a_bloc = params.fetch(:scopes, nil) || params.fetch(:uniq_by, nil) || params.fetch(:if, nil)
        source = a_bloc&.source

        class_name = params[:as].to_s.camelize

        eval <<-RUBY, binding, __FILE__, __LINE__ + 1
          class ::Statisfy::#{class_name}
            include Statisfy::Counter

            #{source || "count(#{params})"}
          end
        RUBY
        @statisfy[params[:as]] = ::Statisfy.const_get(class_name)
      end

      def statisfy
        OpenStruct.new(@statisfy)
      end
    end
  end
end
