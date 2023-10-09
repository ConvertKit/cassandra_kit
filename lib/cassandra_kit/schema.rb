# -*- encoding : utf-8 -*-
require 'cassandra_kit/schema/column'
require 'cassandra_kit/schema/table_desc_dsl'
require 'cassandra_kit/schema/keyspace'
require 'cassandra_kit/schema/migration_validator'
require 'cassandra_kit/schema/table'
require 'cassandra_kit/schema/table_property'
require 'cassandra_kit/schema/table_reader'
require 'cassandra_kit/schema/table_differ'
require 'cassandra_kit/schema/patch'
require 'cassandra_kit/schema/table_updater'
require 'cassandra_kit/schema/table_writer'
require 'cassandra_kit/schema/update_table_dsl'

module CassandraKit
  #
  # The Schema module provides full read/write access to keyspace and table
  # schemas defined in Cassandra.
  #
  # @see Schema::Keyspace
  #
  # @since 1.0.0
  #
  module Schema
  end
end
