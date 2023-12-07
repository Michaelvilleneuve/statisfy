module Statisfy
  module Subscriber
    def self.included(klass)
      klass.extend(ClassMethods)
    end

    module ClassMethods
      def catch_events(*event_names, **options)
        define_method(:should_run?, &options[:if] || -> { true })
        [*event_names].flatten.map do |event_name|
          model_and_event_from_event_name(event_name).tap do |model, event|
            append_callback_to_model(model, event)
            define_subject_method(model)
          end
        end
      end

      def append_callback_to_model(model, event)
        listener = self
        model.class_eval do
          after_commit on: event do
            counter = listener.new
            counter.subject = self

            next unless counter.should_run?

            if listener.respond_to?(Statisfy.configuration.default_async_method)
              listener.send(Statisfy.configuration.default_async_method, attributes)
            else
              counter.perform(attributes)
            end
          end
        end
      end

      def model_and_event_from_event_name(event_name)
        model_with_event = event_name.to_s.split("_")
        event = {
          "created": :create,
          "updated": :update,
          "destroyed": :destroy
        }[model_with_event.pop.to_sym]

        model_name = model_with_event.join("_").camelize

        [Object.const_get(model_name), event]
      rescue NameError
        raise Statisfy::Error, "The model #{model_name} does not exist"
      end

      def define_subject_method(model)
        instance_name = model.name.underscore
        return if method_defined?(instance_name)

        define_method(instance_name) do
          model = instance_name.camelize.constantize
          @subject ||= model.find_by(id: params["id"])
        end
        alias_method :subject, instance_name
      end
    end

    #
    # This is the method that will be called when an event is triggered
    # It will be executed in the background by Sidekiq
    #
    # @resource_or_hash [Hash] The attributes of the model that triggered the event + the previous_changes
    #
    def perform(resource_or_hash)
      @params = resource_or_hash
      process_event
    end
  end
end
