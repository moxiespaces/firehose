module Firehose
  module Security
    class Selector
      attr_reader :filters

      def initialize(selector)
        unless selector.nil? || selector.empty?
          @filters = selector.split(',').map {|str| Filter.new(str)}
        end
      end

      def for_message?(message)
        return true unless filters
        object = 
        !filters.detect do |filter|
          !filter.valid?(message)
        end
      end
    end

    class Filter
      attr_reader :keys, :values

      def initialize(str)
        key, @values = str.split(":", 2)
        @keys = key.split(".")
        @values = @values.split(":")
      end

      def valid?(message)
        value = message
        keys.each do |key|
          return false unless value.is_a?(Hash)
          value = value[key]
        end

        values.include?(value)
      end
    end
  end
end