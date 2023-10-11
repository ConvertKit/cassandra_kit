require File.expand_path('lib/cassandra_kit/version', __dir__)

Gem::Specification.new do |s|
  s.name = 'cassandra_kit'
  s.version = CassandraKit::VERSION
  s.authors = ['Jenny Allar', 'Jess Sumner']
  s.homepage = 'https://github.com/ConvertKit/cassandra_kit'
  s.email = 'engineers@convertkit.com'
  s.license = 'MIT'
  s.summary = 'Full-featured, ActiveModel-compliant ORM for Cassandra using CQL3 but maintained'
  s.description = <<~DESC
    cassandra_kit is an ActiveRecord-like domain model layer for Cassandra that exposes
    the robust data modeling capabilities of CQL3, including parent-child
    relationships via compound primary keys and in-memory atomic manipulation of
    collection columns.
  DESC

  s.files = Dir['lib/**/*.rb', 'templates/**/*', 'spec/**/*.rb', '[A-Z]*']
  s.test_files = Dir['spec/examples/**/*.rb']
  s.required_ruby_version = '>= 2.0'

  s.add_runtime_dependency 'activemodel', '>= 4.0'
  s.add_runtime_dependency 'cassandra-driver', '~> 3.0'
  s.add_development_dependency 'appraisal', '~> 1.0'
  s.add_development_dependency 'rake', '~> 10.1'
  s.add_development_dependency 'rspec', '~> 3.5'
  s.add_development_dependency 'rspec-its', '~> 1.0'
  s.add_development_dependency 'rspec-retry', '~> 0.5'
  s.add_development_dependency 'rubocop', '~> 0.49'
  s.add_development_dependency 'timecop', '~> 0.7'
  s.add_development_dependency 'travis', '~> 1.7'
  s.add_development_dependency 'wwtd', '~> 0.5'
  s.add_development_dependency 'yard', '~> 0.9.20'
  s.requirements << 'Cassandra >= 2.0.0'
end
