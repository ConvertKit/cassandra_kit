# -*- encoding : utf-8 -*-
require 'cassandra_kit/metal/batch'
require 'cassandra_kit/metal/batch_manager'
require 'cassandra_kit/metal/cql_row_specification'
require 'cassandra_kit/metal/data_set'
require 'cassandra_kit/metal/logging'
require 'cassandra_kit/metal/keyspace'
require 'cassandra_kit/metal/request_logger'
require 'cassandra_kit/metal/row'
require 'cassandra_kit/metal/row_specification'
require 'cassandra_kit/metal/statement'
require 'cassandra_kit/metal/writer'
require 'cassandra_kit/metal/deleter'
require 'cassandra_kit/metal/incrementer'
require 'cassandra_kit/metal/inserter'
require 'cassandra_kit/metal/updater'

module CassandraKit
  #
  # The CassandraKit::Metal layer provides a low-level interface to the Cassandra
  # database. Most of the functionality is exposed via the DataSet class, which
  # encapsulates a table with optional filtering, and provides an interface for
  # constructing read and write queries. The Metal layer is not schema-aware,
  # and relies on the user to construct valid CQL queries.
  #
  # @see Keyspace
  # @see DataSet
  # @since 1.0.0
  #
  module Metal
  end
end
