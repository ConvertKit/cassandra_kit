# -*- encoding : utf-8 -*-
require File.expand_path('../spec_helper', __FILE__)

describe CassandraKit::Record::Dirty do
  model :Post do
    key :permalink, :text
    column :title, :text
    set :categories, :text
    column :created_at, :timestamp
  end

  context 'loaded model' do
    let(:created_at_float) { 1455754622.8502421 }
    let(:post) do
      Post.create!(
        permalink: 'cassandra_kit',
        title: 'CassandraKit',
        categories: Set['Libraries'],
        created_at: created_at_float
      )
    end

    it 'should not have changed attributes by default' do
      expect(post.changed_attributes).to be_empty
    end

    it 'should have changed attributes if attributes change' do
      post.title = 'CassandraKit ORM'
      expect(post.changed_attributes).
        to eq({:title => 'CassandraKit'}.with_indifferent_access)
    end

    it 'should not have changed attributes if attribute set to the same thing' do
      post.title = 'CassandraKit'
      expect(post.changed_attributes).to be_empty
    end

    it 'should support *_changed? method' do
      post.title = 'CassandraKit ORM'
      expect(post.title_changed?).to eq(true)
    end

    it 'should not have changed attributes after save' do
      post.title = 'CassandraKit ORM'
      post.save
      expect(post.changed_attributes).to be_empty
    end

    it 'should have previous changes after save' do
      post.title = 'CassandraKit ORM'
      post.save
      expect(post.previous_changes).
        to eq({ :title => ['CassandraKit', 'CassandraKit ORM'] }.with_indifferent_access)
    end

    it 'should detect changes to collections' do
      post.categories << 'Gems'
      expect(post.changes).to eq(
        {categories: [Set['Libraries'], Set['Libraries', 'Gems']]}.
        with_indifferent_access
      )
    end

    it 'should check dirty state against correctly cast timestamp values' do
      post.created_at = created_at_float
      expect(post.changed_attributes).to be_empty
    end
  end

end
