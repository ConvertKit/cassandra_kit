# -*- encoding : utf-8 -*-
module CassandraKit
  #
  # This module adds some utility methods for generating and type-checking UUID
  # objects for use with CassandraKit. These methods are provided because the actual
  # UUID implementation is an artifact of the underlying driver;
  # initializing/typechecking those driver classes directly is potentially
  # breaking.
  #
  module Uuids
    #
    # Create a UUID
    #
    # @param value [Time,String,Integer] timestamp to assign to the UUID, or
    #   numeric or string representation of the UUID
    # @return a UUID appropriate for use with CassandraKit
    #
    def uuid(value = nil)
      if value.nil?
        timeuuid_generator.now
      elsif value.is_a?(Time)
        timeuuid_generator.at(value)
      elsif value.is_a?(DateTime)
        timeuuid_generator.at(Time.at(value.to_f))
      else
        Type::Timeuuid.instance.cast(value)
      end
    end

    #
    # Determine if an object is a UUID
    #
    # @param object an object to check
    # @return [Boolean] true if the object is recognized by CassandraKit as a UUID
    #
    def uuid?(object)
      return true if uuid_in_string?(object)

      object.is_a?(Cassandra::Uuid)
    end

    private

    def uuid_in_string?(object)
      object.is_a?(String) && Cassandra::Uuid.new(object)
    rescue ArgumentError
      false
    end

    def timeuuid_generator
      @timeuuid_generator ||= Cassandra::TimeUuid::Generator.new
    end
  end
end
