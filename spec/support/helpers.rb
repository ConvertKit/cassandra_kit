# -*- encoding : utf-8 -*-
module CassandraKit
  module SpecSupport
    module Macros
      def model(class_name, options = {}, &block)
        return if RSpec.configuration.filter_manager.exclusions
          .include_example?(self)
        setup_models = !self.metadata.key?(:models)
        self.metadata[:models] ||= {}

        metadata[:models][class_name] = [options, block]

        if setup_models
          before :all do
            metadata = self.class.metadata
            metadata[:models].each do |name, (options, block)|
              clazz = Class.new do
                include CassandraKit::Record
                self.table_name = name.to_s.tableize + "_" + SecureRandom.hex(4)
                class_eval(&block)
              end
              Object.module_eval { const_set(name, clazz) }
            end
            metadata[:models].each_key do |name|
              if options.fetch(:synchronize_schema, true)
                Object.const_get(name).synchronize_schema
              end
            end
          end

          before :each do
            metadata = self.class.metadata
            metadata[:models].each_key do |name|
              name.to_s.constantize.find_each(&:destroy)
            end
          end

          after :all do
            self.class.metadata[:models].each_key do |name|
              cassandra_kit.schema.drop_table(Object.const_get(name).table_name)
              Object.module_eval { remove_const(name) }
            end
          end
        end
      end

      def uuid(name)
        let(name) { CassandraKit.uuid }
      end
    end

    module Helpers

      def self.cql_version
        CassandraKit.connect(host: host,
                       port: port,
                       keyspace: "system")
          .execute("SELECT cql_version FROM system.local")
          .first["cql_version"]
      end

      def self.cassandra_kit
        @cassandra_kit ||= CassandraKit.connect(
          host: host,
          port: port,
          keyspace: keyspace_name
        ).tap do |cassandra_kit|
          if ENV['CASSANDRA_KIT_LOG_QUERIES']
            cassandra_kit.logger = Logger.new(STDOUT)
          else
            cassandra_kit.logger = Logger.new(File.open('/dev/null', 'a'))
          end
        end
      end

      def self.host
        ENV['CASSANDRA_KIT_TEST_HOST'] || '127.0.0.1'
      end

      def self.port
        ENV['CASSANDRA_KIT_TEST_PORT'] || '9042'
      end

      def self.legacy_host
        ENV['CASSANDRA_KIT_TEST_LEGACY_HOST'] || '127.0.0.1:9160'
      end

      def self.keyspace_name
        ENV.fetch('CASSANDRA_KIT_TEST_KEYSPACE') do
          test_env_number = ENV['TEST_ENV_NUMBER']
          if test_env_number.present?
            "cassandra_kit_test_#{test_env_number}"
          else
            'cassandra_kit_test'
          end
        end
      end

      def self.legacy_connection
        require 'cassandra-cql'
        @legacy_connection ||= CassandraCQL::Database.new(
          legacy_host,
          :keyspace => keyspace_name,
          :cql_version => '2.0.0'
        )
      end

      def min_uuid(time = Time.now)
        Cassandra::TimeUuid::Generator.new(0, 0).at(time, 0)
      end

      def max_uuid(time = Time.now)
        Cassandra::TimeUuid::Generator.new(0x3fff, 0xffffffffffff).
          at(time, 999)
      end

      def cassandra_kit
        Helpers.cassandra_kit
      end

      def legacy_connection
        Helpers.legacy_connection
      end

      def expect_statement_count(number)
        allow(cassandra_kit.client).to receive(:execute).and_call_original
        yield
        expect(cassandra_kit.client).to have_received(:execute).exactly(number).times
      end

      def disallow_queries!
        expect(cassandra_kit.client).to_not receive(:execute)
      end

      def with_client_error(error)
        allow(cassandra_kit.client).to receive(:execute).once.and_raise(error)
        begin
          yield
        ensure
          allow(cassandra_kit.client).to receive(:execute).and_call_original
        end
      end

      def expect_query_with_consistency(matcher, consistency)
        allow(cassandra_kit.client).to receive(:execute).and_call_original
        yield
        expect(cassandra_kit.client).to have_received(:execute).
          with(matcher, hash_including(:consistency => consistency))
      end

      def expect_query_with_options(matcher, options)
        allow(cassandra_kit.client).to receive(:execute).and_call_original
        yield
        expect(cassandra_kit.client).to have_received(:execute).
          with(matcher, hash_including(options))
      end

      def one_millisecond
        0.001
      end

      def example_slug(example, max_length=1000)
        example.description.downcase.gsub(/[^a-z]+/, '_')[/.{1,#{max_length}}$/]
      end

      # figures a table name starting with `base_name` that is unique to the
      # specified example
      #
      # Examples
      #
      #   let(:table_name) { |ex| unique_table_name("posts", ex) }
      #
      def unique_table_name(base_name, example)
        max_suffix = 45 - base_name.size
        :"#{base_name}_#{example_slug(example, max_suffix)}"
      end
    end
  end
end
