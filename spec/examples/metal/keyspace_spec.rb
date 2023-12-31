# -*- encoding : utf-8 -*-
require_relative '../spec_helper'

describe CassandraKit::Metal::Keyspace do
  before :all do
    cassandra_kit.schema.create_table(:posts) do
      key :id, :int
      column :title, :text
      column :body, :text
    end
  end

  after :each do
    ids = cassandra_kit[:posts].select(:id).map { |row| row[:id] }
    cassandra_kit[:posts].where(id: ids).delete if ids.any?
  end

  after :all do
    cassandra_kit.schema.drop_table(:posts)
  end

  describe '::batch' do
    it 'should send enclosed write statements in bulk' do
      expect_statement_count 1 do
        cassandra_kit.batch do
          cassandra_kit[:posts].insert(id: 1, title: 'Hey')
          cassandra_kit[:posts].where(id: 1).update(body: 'Body')
          cassandra_kit[:posts].where(id: 1).delete(:title)
        end
      end
      expect(cassandra_kit[:posts].first).to eq({id: 1, title: nil, body: 'Body'}
        .with_indifferent_access)
    end

    it 'should auto-apply if option given' do
      cassandra_kit.batch(auto_apply: 2) do
        cassandra_kit[:posts].insert(id: 1, title: 'One')
        expect(cassandra_kit[:posts].to_a.count).to be_zero
        cassandra_kit[:posts].insert(id: 2, title: 'Two')
        expect(cassandra_kit[:posts].to_a.count).to be(2)
      end
    end

    it 'should do nothing if no statements executed in batch' do
      expect { cassandra_kit.batch {} }.to_not raise_error
    end

    it 'should execute unlogged batch if specified' do
      expect_query_with_consistency(instance_of(Cassandra::Statements::Batch::Unlogged), anything) do
        cassandra_kit.batch(unlogged: true) do
          cassandra_kit[:posts].insert(id: 1, title: 'One')
          cassandra_kit[:posts].insert(id: 2, title: 'Two')
        end
      end
    end

    it 'should execute batch with given consistency' do
      expect_query_with_consistency(instance_of(Cassandra::Statements::Batch::Logged), :one) do
        cassandra_kit.batch(consistency: :one) do
          cassandra_kit[:posts].insert(id: 1, title: 'One')
          cassandra_kit[:posts].insert(id: 2, title: 'Two')
        end
      end
    end

    it 'should raise error if consistency specified in individual query in batch' do
      expect {
        cassandra_kit.batch(consistency: :one) do
          cassandra_kit[:posts].consistency(:quorum).insert(id: 1, title: 'One')
        end
      }.to raise_error(ArgumentError)
    end
  end

  describe "#exists?" do
    it "is true for existent keyspaces", :retry => 1, :retry_wait => 1 do
      expect(cassandra_kit.exists?).to eq true
    end

    it "is false for non-existent keyspaces" do
      nonexistent_keyspace = CassandraKit.connect host: CassandraKit::SpecSupport::Helpers.host,
                           port: CassandraKit::SpecSupport::Helpers.port,
                           keyspace: "totallymadeup"

      expect(nonexistent_keyspace.exists?).to be false
    end
  end

  describe "#configure" do
    it "sets load_balancing_policy to DCAwareRoundRobin if datacenter name is present" do
      connection = CassandraKit.connect(host: CassandraKit::SpecSupport::Helpers.host,
                                  port: CassandraKit::SpecSupport::Helpers.port,
                                  datacenter: "datacenter")

      main_policy = connection.load_balancing_policy[:load_balancing_policy]
      inner_policy = main_policy.instance_variable_get("@policy")

      expect(main_policy).not_to be_nil
      expect(main_policy).to be_a(::Cassandra::LoadBalancing::Policies::TokenAware)
      expect(inner_policy).to be_a(::Cassandra::LoadBalancing::Policies::DCAwareRoundRobin)
    end

    it "will leave load_balancing_policy to unset if no datacenter is provided" do
      connection = CassandraKit.connect(host: CassandraKit::SpecSupport::Helpers.host,
                                  port: CassandraKit::SpecSupport::Helpers.port)

      expect(connection.load_balancing_policy).to be_nil
    end
  end

  describe "#drop_table", cql: "~> 3.1" do
    it "allows IF EXISTS" do
      expect { cassandra_kit.schema.drop_table(:unknown) }.to raise_error(Cassandra::Errors::InvalidError)
      expect { cassandra_kit.schema.drop_table(:unknown, exists: true) }.not_to raise_error
    end
  end

  describe "#drop_materialized_view", cql: "~> 3.4" do
    it "allows IF EXISTS" do
      expect { cassandra_kit.schema.drop_materialized_view(:unknown) }.to raise_error(Cassandra::Errors::ConfigurationError)
      expect { cassandra_kit.schema.drop_materialized_view(:unknown, exists: true) }.not_to raise_error
    end
  end

  describe "#ssl_config" do
    it "ssl configuration settings get extracted correctly for sending to cluster" do
      connect = CassandraKit.connect host: CassandraKit::SpecSupport::Helpers.host,
                           port: CassandraKit::SpecSupport::Helpers.port,
                           ssl: true,
                           server_cert: 'path/to/server_cert',
                           client_cert: 'path/to/client_cert',
                           private_key: 'private_key',
                           passphrase: 'passphrase'

      expect(connect.ssl_config[:ssl]).to be true
      expect(connect.ssl_config[:server_cert]).to eq('path/to/server_cert')
      expect(connect.ssl_config[:client_cert]).to eq('path/to/client_cert')
      expect(connect.ssl_config[:private_key]).to eq('private_key')
      expect(connect.ssl_config[:passphrase]).to eq('passphrase')
    end
  end

  describe "#client_compression" do
    let(:client_compression) { :lz4 }
    let(:connect) do
      CassandraKit.connect host: CassandraKit::SpecSupport::Helpers.host,
          port: CassandraKit::SpecSupport::Helpers.port,
          client_compression: client_compression
    end
    it "client compression settings get extracted correctly for sending to cluster" do
      expect(connect.client_compression).to eq client_compression
    end
  end

  describe '#cassandra_options' do
    let(:cassandra_options) { {foo: :bar} }
    let(:connect) do
      CassandraKit.connect host: CassandraKit::SpecSupport::Helpers.host,
          port: CassandraKit::SpecSupport::Helpers.port,
          cassandra_options: cassandra_options
    end
    it 'passes the cassandra options as part of the client options' do
      expect(connect.send(:client_options)).to have_key(:foo)
    end
  end

  describe 'cassandra error handling' do
    let(:connect_options) do
      {
        host: CassandraKit::SpecSupport::Helpers.host,
          port: CassandraKit::SpecSupport::Helpers.port
      }
    end

    let(:default_connect) do
      CassandraKit.connect(connect_options)
    end

    class SpecCassandraErrorHandler
      def initialize(options = {})
      end

      def execute_stmt(keyspace)
        yield
      end
    end

    it 'uses the error handler passed in as a string' do
      obj = CassandraKit.connect connect_options.merge(
          cassandra_error_policy: 'SpecCassandraErrorHandler')

      expect(obj.error_policy.class).to equal(SpecCassandraErrorHandler)
    end

    it 'uses the error handler passed in as a module' do
      obj = CassandraKit.connect connect_options.merge(
          cassandra_error_policy: SpecCassandraErrorHandler)

      expect(obj.error_policy.class).to equal(SpecCassandraErrorHandler)
    end

    it 'uses the instance of an error handler passed in' do
      policy = SpecCassandraErrorHandler.new

      obj = CassandraKit.connect connect_options.merge(
          cassandra_error_policy: policy)

      expect(obj.error_policy).to equal(policy)
    end

    it 'responds to error policy' do
      # Always defined, even if config does not specify it
      expect(default_connect).to respond_to(:error_policy)
    end

    it 'calls execute_stmt on the error policy' do
      policy = ::CassandraKit::Metal::Policy::CassandraError::RetryPolicy.new

      obj = CassandraKit.connect connect_options.merge(
          cassandra_error_policy: policy)
      expect(policy).to receive(:execute_stmt).at_least(:once)
      obj.execute_with_options(CassandraKit::Metal::Statement.new('select * from system.peers;'))
    end

    it 'rejects a negative value for retry delay' do
      expect { CassandraKit.connect connect_options.merge(
        retry_delay: -1.0)
      }.to raise_error(ArgumentError)
    end

    it 'accepts a configured value for retry delay' do
      obj = CassandraKit.connect connect_options.merge(
        retry_delay: 1337.0)

      # do not compare floats exactly, it is error prone
      # the value is passed to the error policy
      expect(obj.error_policy.retry_delay).to be_within(0.1).of(1337.0)
    end

    it 'can clear active connections' do
      expect {
        default_connect.clear_active_connections!
      }.to change {
        default_connect.client
      }
    end
  end

  describe "#execute" do
    let(:statement) { "SELECT id FROM posts" }
    let(:execution_error) { Cassandra::Errors::OverloadedError.new(1,2,3,4,5,6,7,8,9) }

    context "without a connection error" do
      it "executes a CQL query" do
        expect { cassandra_kit.execute(statement) }.not_to raise_error
      end
    end

    context "with a connection error" do
      it "reconnects to cassandra with a new client after no hosts could be reached" do
        allow(cassandra_kit.client)
          .to receive(:execute)
               .with(->(s){ s.cql == statement},
                     hash_including(:consistency => cassandra_kit.default_consistency))
          .and_raise(Cassandra::Errors::NoHostsAvailable)
          .once

        expect { cassandra_kit.execute(statement) }.not_to raise_error
      end

      it "reconnects to cassandra with a new client after execution failed" do
        allow(cassandra_kit.client)
          .to receive(:execute)
               .with(->(s){ s.cql == statement},
                     hash_including(:consistency => cassandra_kit.default_consistency))
          .and_raise(execution_error)
          .once

        expect { cassandra_kit.execute(statement) }.not_to raise_error
      end

      it "reconnects to cassandra with a new client after timeout occurs" do
        allow(cassandra_kit.client)
          .to receive(:execute)
               .with(->(s){ s.cql == statement},
                     hash_including(:consistency => cassandra_kit.default_consistency))
          .and_raise(Cassandra::Errors::TimeoutError)
          .once

        expect { cassandra_kit.execute(statement) }.not_to raise_error
      end
    end
  end

  describe "#prepare_statement" do
    let(:statement) { "SELECT id FROM posts" }
    let(:execution_error) { Cassandra::Errors::OverloadedError.new(1,2,3,4,5,6,7,8,9) }

    context "without a connection error" do
      it "executes a CQL query" do
        expect { cassandra_kit.prepare_statement(statement) }.not_to raise_error
      end
    end

    context "with a connection error" do
      it "reconnects to cassandra with a new client after no hosts could be reached" do
        allow(cassandra_kit.client)
          .to receive(:prepare)
               .with(->(s){ s == statement})
          .and_raise(Cassandra::Errors::NoHostsAvailable)
          .once

        expect { cassandra_kit.prepare_statement(statement) }.not_to raise_error
      end

      it "reconnects to cassandra with a new client after execution failed" do
        allow(cassandra_kit.client)
          .to receive(:prepare)
               .with(->(s){ s == statement})
          .and_raise(execution_error)
          .once

        expect { cassandra_kit.prepare_statement(statement) }.not_to raise_error
      end
    end
  end
end
