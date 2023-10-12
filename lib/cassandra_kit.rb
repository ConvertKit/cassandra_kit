# -*- encoding : utf-8 -*-
require 'delegate'

require 'active_support'
require 'active_support/deprecation'
require 'active_support/core_ext'
require 'cassandra'

require 'cassandra_kit/errors'
require 'cassandra_kit/util'
require 'cassandra_kit/metal/policy/cassandra_error'
require 'cassandra_kit/metal'
require 'cassandra_kit/schema'
require 'cassandra_kit/type'
require 'cassandra_kit/uuids'
require 'cassandra_kit/instrumentation'
require 'cassandra_kit/record'

#
# CassandraKit is a library providing robust data modeling and query building
# capabilities for Cassandra using CQL3.
#
# @see CassandraKit::Record CassandraKit::Record, an object-row mapper for CQL3
# @see CassandraKit::Metal CassandraKit::Metal, a query builder for CQL3 statements
# @see CassandraKit::Schema CassandraKit::Schema::Keyspace, which provides full read-write
#   access to the database schema defined in Cassandra
#
module CassandraKit
  extend CassandraKit::Uuids
  #
  # Get a handle to a keyspace
  #
  # @param (see Metal::Keyspace#initialize)
  # @option (see Metal::Keyspace#initialize)
  # @return [Metal::Keyspace] a handle to a keyspace
  #
  def self.connect(configuration = nil)
    Metal::Keyspace.new(configuration || {})
  end
end
