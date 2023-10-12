# -*- encoding : utf-8 -*-
module CassandraKit
  module Record
    #
    # Rails generator for a default configuration file
    #
    # @since 1.0.0
    #
    class ConfigurationGenerator < Rails::Generators::Base
      namespace 'cassandra_kit:configuration'
      source_root File.expand_path('../../../../templates/', __FILE__)

      def create_configuration
        template "config/cassandra_kit.yml"
      end
    end
  end
end
