# -*- encoding : utf-8 -*-
require File.expand_path('../spec_helper', __FILE__)

describe CassandraKit::Record::Schema do
  context 'CQL3 table' do
    after { cassandra_kit.schema.drop_table(table_name) }
    subject { cassandra_kit.schema.read_table(table_name) }

    let(:table_name) { 'posts_' + SecureRandom.hex(4) }

    let(:model) do
      model_table_name = table_name
      Class.new do
        include CassandraKit::Record
        self.table_name = model_table_name

        key :permalink, :text
        column :title, :text
        list :categories, :text
        set :tags, :text
        map :trackbacks, :timestamp, :text
        table_property :comment, 'Blog Posts'
      end
    end

    context 'new model with simple primary key' do
      before { model.synchronize_schema }

      its(:partition_key_columns) { should == [CassandraKit::Schema::Column.new(:permalink, :text)] }
      its(:data_columns) { should include(CassandraKit::Schema::Column.new(:title, :text)) }
      its(:data_columns) { should include(CassandraKit::Schema::List.new(:categories, :text)) }
      its(:data_columns) { should include(CassandraKit::Schema::Set.new(:tags, :text)) }
      its(:data_columns) { should include(CassandraKit::Schema::Map.new(:trackbacks, :timestamp, :text)) }
      specify { expect(subject.property(:comment)).to eq('Blog Posts') }
    end

    context 'existing model with additional attribute' do
      before do
        cassandra_kit.schema.create_table :posts do
          key :permalink, :text
          column :title, :text
          list :categories, :text
          set :tags, :text
        end
        model.synchronize_schema
      end

      its(:data_columns) { should include(CassandraKit::Schema::Map.new(:trackbacks, :timestamp, :text)) }
    end
  end

  context 'CQL3 table with reversed clustering column' do
    let(:table_name) { 'posts_' + SecureRandom.hex(4) }

    let(:model) do
      model_table_name = table_name
      Class.new do
        include CassandraKit::Record
        self.table_name = model_table_name

        key :blog_id, :uuid
        key :id, :timeuuid, order: :desc
        column :title, :text
      end
    end

    before { model.synchronize_schema }
    after { cassandra_kit.schema.drop_table(table_name) }
    subject { cassandra_kit.schema.read_table(table_name) }

    it 'should order clustering column descending' do
      expect(subject.clustering_columns.first.clustering_order).to eq(:desc)
    end
  end

  context 'CQL3 table with non-dictionary-ordered partition columns' do
    let(:table_name) { 'accesses_' + SecureRandom.hex(4) }

    let(:model) do
      model_table_name = table_name
      Class.new do
        include CassandraKit::Record
        self.table_name = model_table_name

        key :serial, :text, partition: true
        key :username, :text, partition: true
        key :date, :text, partition: true
        key :access_time, :timeuuid
        column :url, :text
      end
    end

    let(:model_modified) do
      model_table_name = table_name
      Class.new do
        include CassandraKit::Record
        self.table_name = model_table_name

        key :serial, :text, partition: true
        key :username, :text, partition: true
        key :date, :text, partition: true
        key :access_time, :timeuuid
        column :url, :text
        column :user_agent, :text
      end
    end

    before { model.synchronize_schema }
    after { cassandra_kit.schema.drop_table(table_name) }

    it 'should be able to synchronize schema again' do
      expect {
        model_modified.synchronize_schema
      }.not_to raise_error
    end
  end

  context 'wide-row legacy table' do
    let(:table_name) { 'legacy_posts_' + SecureRandom.hex(4) }

    let(:legacy_model) do
      model_table_name = table_name
      Class.new do
        include CassandraKit::Record
        self.table_name = model_table_name

        key :blog_subdomain, :text
        key :id, :uuid
        column :data, :text

        compact_storage
      end
    end
    after { cassandra_kit.schema.drop_table(table_name) }
    subject { cassandra_kit.schema.read_table(table_name) }

    context 'new model' do
      before { legacy_model.synchronize_schema }

      its(:partition_key_columns) { should == [CassandraKit::Schema::Column.new(:blog_subdomain, :text)] }
      its(:clustering_columns) { should == [CassandraKit::Schema::Column.new(:id, :uuid)] }
      it { is_expected.to be_compact_storage }
      its(:data_columns) { should == [CassandraKit::Schema::Column.new(:data, :text)] }
    end

    context 'existing model', thrift: true do
      before do
        legacy_connection.execute(<<-CQL2)
          CREATE COLUMNFAMILY #{table_name} (blog_subdomain text PRIMARY KEY)
          WITH comparator=uuid AND default_validation=text
        CQL2
        legacy_model.synchronize_schema
      end

      its(:partition_key_columns) { is_expected.to eq([CassandraKit::Schema::Column.new(:blog_subdomain, :text)]) }
      its(:clustering_columns) { is_expected.to eq([CassandraKit::Schema::Column.new(:id, :uuid)]) }
      it { is_expected.to be_compact_storage }
      its(:data_columns) { is_expected.to eq([CassandraKit::Schema::Column.new(:data, :text)]) }

      it 'should be able to synchronize schema again' do
        expect { legacy_model.synchronize_schema }.to_not raise_error
      end
    end
  end
end
