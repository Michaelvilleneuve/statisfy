module Statisfy
  module Subscriber
    def self.included(klass)
      klass.extend(ClassMethods)
    end

    module ClassMethods
      def catch_events(*event_names)
        [*event_names].flatten.map do |event_name|
          model_and_event_from_event_name(event_name).tap do |model, event|
            append_callback_to_model(model, event)
            define_subject_method(model)
          end
        end
      end

      def append_callback_to_model(model, event)
        listener = self

        statisfy_counter = lambda {
          counter = listener.new
          counter.subject = self
          counter.params = attributes
          counter
        }

        trigger_event = lambda { |statisfy_trigger|
          if listener.respond_to?(Statisfy.configuration.default_async_method) && statisfy_trigger != :destroy
            listener.send(Statisfy.configuration.default_async_method, attributes.merge(statisfy_trigger:))
          else
            instance_exec(&statisfy_counter).perform(attributes.merge(statisfy_trigger:))
          end
        }

        model.class_eval do
          after_commit on: [:destroy] do
            counter = instance_exec(&statisfy_counter)
            next unless counter.decrement_on_destroy? || counter.respond_to?(:on_destroy)

            instance_exec(:destroy, &trigger_event)
          end

          after_commit on: [event] do
            next unless instance_exec(&statisfy_counter).should_run?

            instance_exec(event, &trigger_event)
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
          @subject ||= @params.instance_of?(model) ? @params : model.find_by(id: params["id"])
        end
        alias_method :subject, instance_name
      end
    end

    #
    # This is the method that will be called when an event is triggered
    # It will be executed in the background by Sidekiq
    #
    #
    def perform(resource_or_hash)
      @params = resource_or_hash
      process_event
    end
  end
end
