# -*- encoding : utf-8 -*-
require File.expand_path('../../spec_helper', __FILE__)

describe CassandraKit::Metal::DataSet do
  posts_tn = "posts_#{SecureRandom.hex(4)}"
  post_act_tn = "post_activity_#{SecureRandom.hex(4)}"

  before :all do
    cassandra_kit.schema.create_table(posts_tn) do
      key :blog_subdomain, :text
      key :permalink, :text
      column :title, :text
      column :body, :text
      column :published_at, :timestamp
      list :categories, :text
      set :tags, :text
      map :trackbacks, :timestamp, :text
    end
    cassandra_kit.schema.create_table post_act_tn do
      key :blog_subdomain, :text
      key :permalink, :text
      column :visits, :counter
      column :tweets, :counter
    end
  end

  after :each do
    subdomains = cassandra_kit[posts_tn].select(:blog_subdomain)
                 .map { |row| row[:blog_subdomain] }
    cassandra_kit[posts_tn].where(blog_subdomain: subdomains).delete if subdomains.any?
  end

  after :all do
    cassandra_kit.schema.drop_table(posts_tn)
    cassandra_kit.schema.drop_table(post_act_tn)
  end

  let(:row_keys) { {blog_subdomain: 'cassandra', permalink: 'big-data'} }

  describe '#insert' do
    let(:row) do
      row_keys.merge(
        title: 'Fun times',
        categories: ['Fun', 'Profit'],
        tags: Set['cassandra', 'big-data'],
        trackbacks: {
          Time.at(Time.now.to_i) => 'www.google.com',
          Time.at(Time.now.to_i - 60) => 'www.yahoo.com'
        }
      )
    end

    it 'should insert a row' do
      cassandra_kit[posts_tn].insert(row)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:title]).to eq('Fun times')
    end

    # TODO: test is currently failing locally. At this time I am not sure if
    # this is functionality we would hope to keep with the paired down gem.
    # Investigation is needed if this functionality continues to be valuable.
    xit 'should insert a record when multi-DC option of on' do
      connection = CassandraKit.connect(host: CassandraKit::SpecSupport::Helpers.host,
                                  port: CassandraKit::SpecSupport::Helpers.port,
                                  keyspace: CassandraKit::SpecSupport::Helpers.keyspace_name,
                                  datacenter: 1)

      connection[posts_tn].insert(row)
      expect(connection[posts_tn].where(row_keys).first[:title]).to eq('Fun times')
    end

    it 'should correctly insert a list' do
      cassandra_kit[posts_tn].insert(row)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).
        to eq(['Fun', 'Profit'])
    end

    it 'should correctly insert a set' do
      cassandra_kit[posts_tn].insert(row)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:tags]).
        to eq(Set['cassandra', 'big-data'])
    end

    it 'should correctly insert a map' do
      cassandra_kit[posts_tn].insert(row)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:trackbacks]).
        to eq(row[:trackbacks])
    end

    it 'should include ttl argument' do
      cassandra_kit[posts_tn].insert(row, :ttl => 10.minutes)
      expect(cassandra_kit[posts_tn].select_ttl(:title).where(row_keys).first.ttl(:title)).
        to be_within(5).of(10.minutes)
    end

    it 'should include timestamp argument' do
      cassandra_kit.schema.truncate_table(posts_tn)
      time = 1.day.ago
      cassandra_kit[posts_tn].insert(row, :timestamp => time)
      expect(cassandra_kit[posts_tn].select_writetime(:title).where(row_keys).
        first.writetime(:title)).to eq((time.to_f * 1_000_000).to_i)
    end

    it 'should insert row with given consistency' do
      expect_query_with_consistency(->(s){/INSERT/ === s.cql}, :one) do
        cassandra_kit[posts_tn].insert(row, consistency: :one)
      end
    end

    it 'should include multiple arguments joined by AND' do
      cassandra_kit.schema.truncate_table(posts_tn)
      time = 1.day.ago
      cassandra_kit[posts_tn].insert(row, :ttl => 600, :timestamp => time)
      result = cassandra_kit[posts_tn].select_ttl(:title).select_writetime(:title).
        where(row_keys).first
      expect(result.writetime(:title)).to eq((time.to_f * 1_000_000).to_i)
      expect(result.ttl(:title)).to be_within(5).of(10.minutes)
    end
  end

  describe '#update' do
    it 'should send basic update statement' do
      cassandra_kit[posts_tn].where(row_keys).
        update(:title => 'Fun times', :body => 'Fun')
      expect(cassandra_kit[posts_tn].where(row_keys).
        first[:title]).to eq('Fun times')
    end

    it 'should send update statement with options' do
      cassandra_kit.schema.truncate_table(posts_tn)
      time = Time.now - 10.minutes

      cassandra_kit[posts_tn].where(row_keys).
        update({title: 'Fun times', body: 'Fun'}, ttl: 600, timestamp: time)

      row = cassandra_kit[posts_tn].
        select_ttl(:title).select_writetime(:title).
        where(row_keys).first

      expect(row.ttl(:title)).to be_within(5).of(10.minutes)
      expect(row.writetime(:title)).to eq((time.to_f * 1_000_000).to_i)
    end

    it 'should send update statement with given consistency' do
      expect_query_with_consistency(->(s){/UPDATE/ === s.cql}, :one) do
        cassandra_kit[posts_tn].where(row_keys).update(
          {title: 'Marshmallows'}, consistency: :one)
      end
    end

    it 'should overwrite list column' do
      cassandra_kit[posts_tn].where(row_keys).
        update(categories: ['Big Data', 'Cassandra'])
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).
        to eq(['Big Data', 'Cassandra'])
    end

    it 'should overwrite set column' do
      cassandra_kit[posts_tn].where(row_keys).update(tags: Set['big-data', 'nosql'])
      expect(cassandra_kit[posts_tn].where(row_keys).first[:tags]).
        to eq(Set['big-data', 'nosql'])
    end

    it 'should overwrite map column' do
      time1 = Time.at(Time.now.to_i)
      time2 = Time.at(10.minutes.ago.to_i)
      cassandra_kit[posts_tn].where(row_keys).update(
        trackbacks: {time1 => 'foo', time2 => 'bar'})
      expect(cassandra_kit[posts_tn].where(row_keys).first[:trackbacks]).
        to eq({time1 => 'foo', time2 => 'bar'})
    end

    it 'should perform various types of update in one go' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(title: 'Big Data',
                       body: 'Cassandra',
                       categories: ['Scalability']))
      cassandra_kit[posts_tn].where(row_keys).update do
        set(title: 'Bigger Data')
        list_append(:categories, 'Fault-Tolerance')
      end
      expect(cassandra_kit[posts_tn].where(row_keys).first[:title]).to eq('Bigger Data')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).
        to eq(%w(Scalability Fault-Tolerance))
    end

    it 'should use the last value set for a given column' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(title: 'Big Data',
                       body: 'Cassandra',
                       categories: ['Scalability']))
      cassandra_kit[posts_tn].where(row_keys).update do
        set(title: 'Bigger Data')
        set(title: 'Even Bigger Data')
      end
      expect(cassandra_kit[posts_tn].where(row_keys).first[:title]).to eq('Even Bigger Data')
    end
  end

  describe '#list_prepend' do
    it 'should prepend a single element to list column' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra']))
      cassandra_kit[posts_tn].where(row_keys).
        list_prepend(:categories, 'Scalability')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(
        ['Scalability', 'Big Data', 'Cassandra']
      )
    end

    # breaks in Cassandra 2.0.13+ or 2.1.3+ because reverse order bug was fixed:
    # https://issues.apache.org/jira/browse/CASSANDRA-8733
    it 'should prepend multiple elements to list column' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra']))
      cassandra_kit[posts_tn].where(row_keys).
        list_prepend(:categories, ['Scalability', 'Partition Tolerance'])

      expected = if cassandra_kit.bug8733_version?
        ['Partition Tolerance', 'Scalability', 'Big Data', 'Cassandra']
      else
        ['Scalability', 'Partition Tolerance', 'Big Data', 'Cassandra']
      end

      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(expected)
    end
  end

  describe '#list_append' do
    it 'should append single element to list column' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra']))
      cassandra_kit[posts_tn].where(row_keys).
        list_append(:categories, 'Scalability')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(
        ['Big Data', 'Cassandra', 'Scalability']
      )
    end

    it 'should append multiple elements to list column' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra']))
      cassandra_kit[posts_tn].where(row_keys).
        list_append(:categories, ['Scalability', 'Partition Tolerance'])
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(
        ['Big Data', 'Cassandra', 'Scalability', 'Partition Tolerance']
      )
    end
  end

  describe '#list_replace' do
    it 'should add to list at specified index' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra', 'Scalability']))
      cassandra_kit[posts_tn].where(row_keys).
        list_replace(:categories, 1, 'C*')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(
        ['Big Data', 'C*', 'Scalability']
      )
    end
  end

  describe '#list_remove' do
    it 'should remove from list by specified value' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra', 'Scalability']))
      cassandra_kit[posts_tn].where(row_keys).
        list_remove(:categories, 'Cassandra')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(
        ['Big Data', 'Scalability']
      )
    end

    it 'should remove from list by multiple values' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(categories: ['Big Data', 'Cassandra', 'Scalability']))
      cassandra_kit[posts_tn].where(row_keys).
        list_remove(:categories, ['Big Data', 'Cassandra'])
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).to eq(
        ['Scalability']
      )
    end
  end

  describe '#set_add' do
    it 'should add one element to set' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(tags: Set['big-data', 'nosql']))
      cassandra_kit[posts_tn].where(row_keys).set_add(:tags, 'cassandra')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:tags]).
        to eq(Set['big-data', 'nosql', 'cassandra'])
    end

    it 'should add multiple elements to set' do
      cassandra_kit[posts_tn].insert(row_keys.merge(tags: Set['big-data', 'nosql']))
      cassandra_kit[posts_tn].where(row_keys).set_add(:tags, 'cassandra')

      expect(cassandra_kit[posts_tn].where(row_keys).first[:tags]).
        to eq(Set['big-data', 'nosql', 'cassandra'])
    end
  end

  describe '#set_remove' do
    it 'should remove elements from set' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(tags: Set['big-data', 'nosql', 'cassandra']))
      cassandra_kit[posts_tn].where(row_keys).set_remove(:tags, 'cassandra')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:tags]).
        to eq(Set['big-data', 'nosql'])
    end

    it 'should remove multiple elements from set' do
      cassandra_kit[posts_tn].insert(
        row_keys.merge(tags: Set['big-data', 'nosql', 'cassandra']))
      cassandra_kit[posts_tn].where(row_keys).
        set_remove(:tags, Set['nosql', 'cassandra'])
      expect(cassandra_kit[posts_tn].where(row_keys).first[:tags]).
        to eq(Set['big-data'])
    end
  end

  describe '#map_update' do
    it 'should update specified map key with value' do
      time1 = Time.at(Time.now.to_i)
      time2 = Time.at(10.minutes.ago.to_i)
      time3 = Time.at(1.hour.ago.to_i)
      cassandra_kit[posts_tn].insert(row_keys.merge(
        trackbacks: {time1 => 'foo', time2 => 'bar'}))
      cassandra_kit[posts_tn].where(row_keys).map_update(:trackbacks, time3 => 'baz')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:trackbacks]).
        to eq({time1 => 'foo', time2 => 'bar', time3 => 'baz'})
    end

    it 'should update specified map key with multiple values' do
      time1 = Time.at(Time.now.to_i)
      time2 = Time.at(10.minutes.ago.to_i)
      time3 = Time.at(1.hour.ago.to_i)
      cassandra_kit[posts_tn].insert(row_keys.merge(
        trackbacks: {time1 => 'foo', time2 => 'bar'}))
      cassandra_kit[posts_tn].where(row_keys).
        map_update(:trackbacks, time1 => 'FOO', time3 => 'baz')
      expect(cassandra_kit[posts_tn].where(row_keys).first[:trackbacks]).
        to eq({time1 => 'FOO', time2 => 'bar', time3 => 'baz'})
    end
  end

  describe '#increment' do
    after { cassandra_kit.schema.truncate_table(post_act_tn) }

    it 'should increment counter columns' do
      cassandra_kit[post_act_tn].
        where(row_keys).
        increment(visits: 1, tweets: 2)

      row = cassandra_kit[post_act_tn].where(row_keys).first

      expect(row[:visits]).to eq(1)
      expect(row[:tweets]).to eq(2)
    end
  end

  describe '#decrement' do
    after { cassandra_kit.schema.truncate_table(post_act_tn) }

    it 'should decrement counter columns' do
      cassandra_kit[post_act_tn].where(row_keys).
        decrement(visits: 1, tweets: 2)

      row = cassandra_kit[post_act_tn].where(row_keys).first
      expect(row[:visits]).to eq(-1)
      expect(row[:tweets]).to eq(-2)
    end
  end

  describe '#delete' do
    before do
      cassandra_kit[posts_tn].
        insert(row_keys.merge(title: 'Big Data', body: 'It\'s big.'))
    end

    it 'should send basic delete statement' do
      cassandra_kit[posts_tn].where(row_keys).delete
      expect(cassandra_kit[posts_tn].where(row_keys).first).to be_nil
    end

    it 'should send delete statement for specified columns' do
      cassandra_kit[posts_tn].where(row_keys).delete(:body)
      row = cassandra_kit[posts_tn].where(row_keys).first
      expect(row[:body]).to be_nil
      expect(row[:title]).to eq('Big Data')
    end

    it 'should send delete statement with writetime option' do
      time = Time.now - 10.minutes

      cassandra_kit[posts_tn].where(row_keys).delete(
        :body, :timestamp => time
      )
      row = cassandra_kit[posts_tn].select(:body).where(row_keys).first
      expect(row[:body]).to eq('It\'s big.')
      # This means timestamp is working, since the earlier timestamp would cause
      # Cassandra to ignore the deletion
    end

    it 'should send delete with specified consistency' do
      expect_query_with_consistency(->(s){/DELETE/ === s.cql}, :one) do
        cassandra_kit[posts_tn].where(row_keys).delete(:body, :consistency => :one)
      end
    end
  end

  describe '#list_remove_at' do
    it 'should remove element at specified position from list' do
      cassandra_kit[posts_tn].
        insert(row_keys.merge(categories: ['Big Data', 'NoSQL', 'Cassandra']))
      cassandra_kit[posts_tn].where(row_keys).list_remove_at(:categories, 1)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).
        to eq(['Big Data', 'Cassandra'])
    end

    it 'should remove element at specified positions from list' do
      cassandra_kit[posts_tn].
        insert(row_keys.merge(categories: ['Big Data', 'NoSQL', 'Cassandra']))
      cassandra_kit[posts_tn].where(row_keys).list_remove_at(:categories, 0, 2)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:categories]).
        to eq(['NoSQL'])
    end
  end

  describe '#map_remove' do
    it 'should remove one element from a map' do
      time1 = Time.at(Time.now.to_i)
      time2 = Time.at(10.minutes.ago.to_i)
      time3 = Time.at(1.hour.ago.to_i)
      cassandra_kit[posts_tn].insert(row_keys.merge(
        trackbacks: {time1 => 'foo', time2 => 'bar', time3 => 'baz'}))
      cassandra_kit[posts_tn].where(row_keys).map_remove(:trackbacks, time2)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:trackbacks]).
        to eq({time1 => 'foo', time3 => 'baz'})
    end

    it 'should remove multiple elements from a map' do
      time1 = Time.at(Time.now.to_i)
      time2 = Time.at(10.minutes.ago.to_i)
      time3 = Time.at(1.hour.ago.to_i)
      cassandra_kit[posts_tn].insert(row_keys.merge(
        trackbacks: {time1 => 'foo', time2 => 'bar', time3 => 'baz'}))
      cassandra_kit[posts_tn].where(row_keys).map_remove(:trackbacks, time1, time3)
      expect(cassandra_kit[posts_tn].where(row_keys).first[:trackbacks]).
        to eq({time2 => 'bar'})
    end
  end

  describe '#cql' do
    it 'should generate select statement with all columns' do
      expect(cassandra_kit[posts_tn].cql.to_s).to eq("SELECT * FROM #{posts_tn}")
    end
  end

  describe '#select' do
    before do
      cassandra_kit[posts_tn].insert(row_keys.merge(
        title: 'Big Data',
        body: 'Fault Tolerance',
        published_at: Time.now
      ))
    end

    it 'should generate select statement with given columns' do
      expect(cassandra_kit[posts_tn].select(:title, :body).where(row_keys).first.
        keys).to eq(%w(title body))
    end

    it 'should accept array argument' do
      expect(cassandra_kit[posts_tn].select([:title, :body]).where(row_keys).first.
        keys).to eq(%w(title body))
    end

    it 'should combine multiple selects' do
      expect(cassandra_kit[posts_tn].select(:title).select(:body).where(row_keys).first.
        keys).to eq(%w(title body))
    end
  end

  describe '#select!' do
    before do
      cassandra_kit[posts_tn].insert(row_keys.merge(
        title: 'Big Data',
        body: 'Fault Tolerance',
        published_at: Time.now
      ))
    end

    it 'should override select statement with given columns' do
      expect(cassandra_kit[posts_tn].select(:title, :body).select!(:published_at).
        where(row_keys).first.keys).to eq(%w(published_at))
    end
  end

  describe '#where' do
    before do
      cassandra_kit[posts_tn].insert(row_keys.merge(
        title: 'Big Data',
        body: 'Fault Tolerance',
        published_at: Time.now
      ))
    end

    it 'should build WHERE statement from hash' do
      expect(cassandra_kit[posts_tn].where(blog_subdomain: row_keys[:blog_subdomain]).
        first[:title]).to eq('Big Data')
      expect(cassandra_kit[posts_tn].where(blog_subdomain: 'foo').first).to be_nil
    end

    it 'should build WHERE statement from multi-element hash' do
      expect(cassandra_kit[posts_tn].where(row_keys).first[:title]).to eq('Big Data')
      expect(cassandra_kit[posts_tn].where(row_keys.merge(:permalink => 'foo')).
        first).to be_nil
    end

    it 'should build WHERE statement with IN' do
      cassandra_kit[posts_tn].insert(row_keys.merge(
        blog_subdomain: 'big-data-weekly',
        title: 'Cassandra',
      ))
      cassandra_kit[posts_tn].insert(row_keys.merge(
        blog_subdomain: 'bogus-blog',
        title: 'Bogus Post',
      ))
      expect(cassandra_kit[posts_tn].where(
        :blog_subdomain => %w(cassandra big-data-weekly)
      ).map { |row| row[:title] }).to match_array(['Big Data', 'Cassandra'])
    end

    it 'should use = if provided one-element array' do
      expect(cassandra_kit[posts_tn].
        where(row_keys.merge(blog_subdomain: [row_keys[:blog_subdomain]])).
        first[:title]).to eq('Big Data')
    end

    it 'should build WHERE statement from CQL string' do
      expect(cassandra_kit[posts_tn].where("blog_subdomain = '#{row_keys[:blog_subdomain]}'").
        first[:title]).to eq('Big Data')
    end

    it 'should build WHERE statement from CQL string with bind variables' do
      expect(cassandra_kit[posts_tn].where("blog_subdomain = ?", row_keys[:blog_subdomain]).
        first[:title]).to eq('Big Data')
    end

    it 'should aggregate multiple WHERE statements' do
      expect(cassandra_kit[posts_tn].where(:blog_subdomain => row_keys[:blog_subdomain]).
        where('permalink = ?', row_keys[:permalink]).
        first[:title]).to eq('Big Data')
    end

  end

  describe '#where!' do
    before do
      cassandra_kit[posts_tn].insert(row_keys.merge(
        title: 'Big Data',
        body: 'Fault Tolerance',
        published_at: Time.now
      ))
    end

    it 'should override chained conditions' do
      expect(cassandra_kit[posts_tn].where(:permalink => 'bogus').
        where!(:blog_subdomain => row_keys[:blog_subdomain]).
        first[:title]).to eq('Big Data')
    end
  end

  describe '#limit' do
    before do
      cassandra_kit[posts_tn].insert(row_keys.merge(title: 'Big Data'))
      cassandra_kit[posts_tn].insert(
        row_keys.merge(permalink: 'marshmallows', title: 'Marshmallows'))
      cassandra_kit[posts_tn].insert(
        row_keys.merge(permalink: 'zz-top', title: 'ZZ Top'))
    end

    it 'should add LIMIT' do
      expect(cassandra_kit[posts_tn].where(row_keys.slice(:blog_subdomain)).limit(2).
        map { |row| row[:title] }).to eq(['Big Data', 'Marshmallows'])
    end
  end

  describe '#order' do
    before do
      cassandra_kit[posts_tn].insert(row_keys.merge(title: 'Big Data'))
      cassandra_kit[posts_tn].insert(
        row_keys.merge(permalink: 'marshmallows', title: 'Marshmallows'))
      cassandra_kit[posts_tn].insert(
        row_keys.merge(permalink: 'zz-top', title: 'ZZ Top'))
    end

    it 'should add order' do
      expect(cassandra_kit[posts_tn].where(row_keys.slice(:blog_subdomain)).
        order(permalink: 'desc').map { |row| row[:title] }).
        to eq(['ZZ Top', 'Marshmallows', 'Big Data'])
    end
  end

  describe '#consistency' do
    let(:data_set) { cassandra_kit[posts_tn].consistency(:one) }

    it 'should issue SELECT with scoped consistency' do
      expect_query_with_consistency(anything, :one) { data_set.to_a }
    end

    it 'should issue INSERT with scoped consistency' do
      expect_query_with_consistency(anything, :one) do
        data_set.insert(row_keys)
      end
    end

    it 'should issue UPDATE with scoped consistency' do
      expect_query_with_consistency(anything, :one) do
        data_set.where(row_keys).update(title: 'Marshmallows')
      end
    end

    it 'should issue DELETE with scoped consistency' do
      expect_query_with_consistency(anything, :one) do
        data_set.where(row_keys).delete
      end
    end

    it 'should issue DELETE column with scoped consistency' do
      expect_query_with_consistency(anything, :one) do
        data_set.where(row_keys).delete(:title)
      end
    end
  end

  describe 'default consistency' do
    before(:all) { cassandra_kit.default_consistency = :all }
    after(:all) { cassandra_kit.default_consistency = nil }
    let(:data_set) { cassandra_kit[posts_tn] }

    it 'should issue SELECT with default consistency' do
      expect_query_with_consistency(anything, :all) { data_set.to_a }
    end

    it 'should issue INSERT with default consistency' do
      expect_query_with_consistency(anything, :all) do
        data_set.insert(row_keys)
      end
    end

    it 'should issue UPDATE with default consistency' do
      expect_query_with_consistency(anything, :all) do
        data_set.where(row_keys).update(title: 'Marshmallows')
      end
    end

    it 'should issue DELETE with default consistency' do
      expect_query_with_consistency(anything, :all) do
        data_set.where(row_keys).delete
      end
    end

    it 'should issue DELETE column with default consistency' do
      expect_query_with_consistency(anything, :all) do
        data_set.where(row_keys).delete(:title)
      end
    end
  end

  describe '#page_size' do
    let(:data_set) { cassandra_kit[posts_tn].page_size(1) }

    it 'should issue SELECT with scoped page size' do
      expect_query_with_options(->(s){/SELECT/ === s.cql}, :page_size => 1) { data_set.to_a }
    end
  end

  describe '#paging_state' do
    let(:data_set) { cassandra_kit[posts_tn].paging_state(nil) }

    it 'should issue SELECT with scoped paging state' do
      expect_query_with_options(->(s){/SELECT/ === s.cql}, :paging_state => nil) { data_set.to_a }
    end
  end

  describe 'result enumeration' do
    let(:row) { row_keys.merge(:title => 'Big Data') }

    before do
      cassandra_kit[posts_tn].insert(row)
    end

    it 'should enumerate over results' do
      expect(cassandra_kit[posts_tn].to_a.map { |row| row.select { |k, v| v }}).
        to eq([row.stringify_keys])
    end

    it 'should provide results with indifferent access' do
      expect(cassandra_kit[posts_tn].to_a.first[:blog_permalink]).
        to eq(row_keys[:blog_permalink])
    end

    it 'should not run query if no block given to #each' do
      expect { cassandra_kit[posts_tn].each }.to_not raise_error
    end

    it 'should return Enumerator if no block given to #each' do
      expect(cassandra_kit[posts_tn].each.each_with_index.
        map { |row, i| [row[:blog_permalink], i] }).
        to eq([[row[:blog_permalink], 0]])
    end
  end

  describe '#first' do
    let(:row) { row_keys.merge(:title => 'Big Data') }

    before do
      cassandra_kit[posts_tn].insert(row)
      cassandra_kit[posts_tn].insert(
        row_keys.merge(:permalink => 'zz-top', :title => 'ZZ Top'))
    end

    it 'should run a query with LIMIT 1 and return first row' do
      expect(cassandra_kit[posts_tn].first.select { |k, v| v }).to eq(row.stringify_keys)
    end
  end

  describe '#count' do
    before do
      4.times do |i|
        cassandra_kit[posts_tn].insert(row_keys.merge(
          permalink: "post-#{i}", title: "Post #{i}"))
      end
    end

    it 'should raise DangerousQueryError when attempting to count' do
      expect{ cassandra_kit[posts_tn].count }.to raise_error(CassandraKit::Record::DangerousQueryError)
    end

    it 'should raise DangerousQueryError when attempting to access size' do
      expect{ cassandra_kit[posts_tn].size }.to raise_error(CassandraKit::Record::DangerousQueryError)
    end

    it 'should raise DangerousQueryError when attempting to access length' do
      expect{ cassandra_kit[posts_tn].length }.to raise_error(CassandraKit::Record::DangerousQueryError)
    end
  end
end
