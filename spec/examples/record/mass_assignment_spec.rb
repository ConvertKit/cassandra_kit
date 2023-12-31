# -*- encoding : utf-8 -*-
require_relative 'spec_helper'

describe CassandraKit::Record::MassAssignment do
  context 'with strong parameters', rails: '>= 4.0' do
    model :Post do
      key :permalink, :text
      column :title, :text
    end

    it 'should allow assignment of vanilla hash' do
      expect(Post.new(:title => 'CassandraKit').title).to eq('CassandraKit')
    end

    it 'should allow assignment of permitted strong params' do
      expect(Post.new(StrongParams.new(true, :title => 'CassandraKit')).title).
        to eq('CassandraKit')
    end

    it 'should raise exception when assigned non-permitted strong params' do
      expect { Post.new(StrongParams.new(false, :title => 'CassandraKit')) }.
        to raise_error(ActiveModel::ForbiddenAttributesError)
    end

    class StrongParams < DelegateClass(Hash)
      def initialize(permitted, params)
        super(params)
        @permitted = !!permitted
      end

      def permitted?
        @permitted
      end
    end
  end

  context 'with mass-assignment protection', rails: '~> 3.0' do
    model :Post do
      key :permalink, :text
      column :title, :text
      column :page_views, :int

      attr_accessible :title
    end

    let(:post) { Post.new(:title => 'CassandraKit', :page_views => 1000) }

    it 'should allow assignment of accessible params' do
      expect(post.title).to eq('CassandraKit')
    end

    it 'should not allow assignment of inaccessible params' do
      expect(post.page_views).to be_nil
    end
  end
end
