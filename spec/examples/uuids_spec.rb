# -*- encoding : utf-8 -*-
require_relative 'spec_helper'

describe CassandraKit::Uuids do
  describe '#uuid' do
    specify { CassandraKit.uuid.is_a?(Cassandra::TimeUuid) }
    specify { CassandraKit.uuid != CassandraKit.uuid }
    specify { time = Time.now; CassandraKit.uuid(time).to_time == time }
    specify { time = DateTime.now; CassandraKit.uuid(time).to_time == time.to_time }
    specify { time = Time.zone.now; CassandraKit.uuid(time).to_time == time.to_time }
    specify { val = CassandraKit.uuid.value; CassandraKit.uuid(val).value == val }
    specify { str = CassandraKit.uuid.to_s; CassandraKit.uuid(str).to_s == str }
  end

  describe '#uuid?' do
    specify { CassandraKit.uuid?(CassandraKit.uuid) }
    specify { !CassandraKit.uuid?(CassandraKit.uuid.to_s) }
    if defined? SimpleUUID::UUID
      specify { !CassandraKit.uuid?(SimpleUUID::UUID.new) }
    end
  end
end
