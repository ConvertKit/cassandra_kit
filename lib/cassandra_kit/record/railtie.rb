# -*- encoding : utf-8 -*-
require 'i18n/core_ext/hash'
require 'yaml'
require 'erb'

module CassandraKit
  module Record
    # @private
    # @since 0.1.0
    class Railtie < Rails::Railtie
      config.cassandra_kit = Record

      def self.app_name
        Rails.application.railtie_name.sub(/_application$/, '')
      end

      initializer "cassandra_kit.configure_rails" do
        connection = CassandraKit.connect(configuration)

        connection.logger = Rails.logger
        Record.connection = connection
      end

      initializer "cassandra_kit.add_new_relic" do
        if configuration.fetch(:newrelic, true)
          begin
            require 'new_relic/agent/datastores'
          rescue LoadError => e
            Rails.logger.debug(
              "New Relic not installed; skipping New Relic integration")
          else
            require 'cassandra_kit/metal/new_relic_instrumentation'
          end
        end
      end

      rake_tasks do
        require "cassandra_kit/record/tasks"
      end

      generators do
        require 'cassandra_kit/record/configuration_generator'
        require 'cassandra_kit/record/record_generator'
      end

      private

      def configuration
        return @configuration if defined? @configuration

        config_path = Rails.root.join('config/cassandra_kit.yml').to_s

        if File.exist?(config_path)
          config_yaml = ERB.new(File.read(config_path)).result
          @configuration = YAML.load(config_yaml)[Rails.env]
            .deep_symbolize_keys
        else
          @configuration = {host: '127.0.0.1:9042'}
        end
        @configuration
          .reverse_merge!(keyspace: "#{Railtie.app_name}_#{Rails.env}")

        @configuration
      end
    end
  end
end
