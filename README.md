# CassandraKit #

CassandraKit is a Ruby ORM for [Cassandra](http://cassandra.apache.org/) using
[CQL3][].

`CassandraKit::Record` is an ActiveRecord-like domain model layer that exposes
the robust data modeling capabilities of CQL3, including parent-child
relationships via compound primary keys and collection columns.

The lower-level `CassandraKit::Metal` layer provides a CQL query builder interface
inspired by the excellent [Sequel](http://sequel.rubyforge.org/) library.

## Installation ##

Add it to your Gemfile:

``` ruby
gem 'cassandra_kit'
```

# TODO - verify if this is still true
If you use Rails 5, add this:
``` ruby
gem 'activemodel-serializers-xml'
```

### Rails integration ###

CassandraKit does not require Rails, but if you are using Rails, you
will need version 3.2+. CassandraKit::Record will read from the configuration file
`config/cassandra_kit.yml` if it is present. You can generate a default configuration
file with:

```bash
rails g cassandra_kit:configuration
```

Once you've got things configured (or decided to accept the defaults), run this
to create your keyspace (database):

```bash
rake cassandra_kit:keyspace:create
```

## Setting up Models ##

Unlike in ActiveRecord, models declare their properties inline. We'll start with
a simple `Blog` model:

```ruby
class Blog
  include CassandraKit::Record

  key :subdomain, :text
  column :name, :text
  column :description, :text
end
```

Unlike a relational database, Cassandra does not have auto-incrementing primary
keys, so you must explicitly set the primary key when you create a new model.
For blogs, we use a natural key, which is the subdomain. Another option is to
use a UUID.

### Compound keys and parent-child relationships ###

While Cassandra is not a relational database, compound keys do naturally map
to parent-child relationships. CassandraKit supports this explicitly with the
`has_many` and `belongs_to` relations. Let's create a model for posts that acts
as the child of the blog model:

```ruby
class Post
  include CassandraKit::Record
  belongs_to :blog
  key :id, :timeuuid, auto: true
  column :title, :text
  column :body, :text
end
```

The `auto` option for the `key` declaration means CassandraKit will initialize new
records with a UUID already generated. This option is only valid for `:uuid` and
`:timeuuid` key columns.

The `belongs_to` association accepts a `:foreign_key` option which allows you to
specify the attribute used as the partition key.

Note that the `belongs_to` declaration must come *before* the `key` declaration.
This is because `belongs_to` defines the
[partition key](http://docs.datastax.com/en/glossary/doc/glossary/gloss_partition_key.html); the `id` column is
the [clustering column](http://docs.datastax.com/en/glossary/doc/glossary/gloss_clustering_column.html).

Practically speaking, this means that posts are accessed using both the
`blog_subdomain` (automatically defined by the `belongs_to` association) and the
`id`. The most natural way to represent this type of lookup is using a
`has_many` association. Let's add one to `Blog`:

```ruby
class Blog
  include CassandraKit::Record

  key :subdomain, :text
  column :name, :text
  column :description, :text

  has_many :posts
end
```

Now we might do something like this:

```ruby
class PostsController < ActionController::Base
  def show
    Blog.find(current_subdomain).posts.find(params[:id])
  end
end
```

Parent child relationship in a namespaced model can be defined using the `class_name` option of `belongs_to` method as follows:

```ruby
module Blogger
  class Blog
    include CassandraKit::Record

    key :subdomain, :text
    column :name, :text
    column :description, :text

    has_many :posts
  end
end

module Blogger
  class Post
    include CassandraKit::Record

    belongs_to :blog, class_name: 'Blogger::Blog'
    key :id, :timeuuid, auto: true
    column :title, :text
    column :body, :text
  end
end
```

### Compound Partition Keys ###

If you wish to declare a compound partition key in a model, you can do something like:

```ruby
class Post
  include CassandraKit::Record

  key :country, :text, partition: true
  key :blog, :text, partition: true
  key :id, :timeuuid, auto: true
  column :title, :text
  column :body, :text
end
```

Your compound partition key here is `(country, blog)`, and the entire compound primary key is `((country, blog), id)`.
Any key values defined after the last partition key value are clustering columns.

### Timestamps ###

If your final primary key column is a `timeuuid` with the `:auto` option set,
the `created_at` method will return the time that the UUID key was generated.

To add timestamp columns, simply use the `timestamps` class macro:

```ruby
class Blog
  include CassandraKit::Record

  key :subdomain, :text
  column :name, :text
  timestamps
end
```

This will automatically define `created_at` and `updated_at` columns, and
populate them appropriately on save.

If the creation time can be extracted from the primary key as outlined above,
this method will be preferred and no `created_at` column will be defined.

### Enums ###

If your a column should behave like an `ActiveRecord::Enum` you can use the
column type `:enum`. It will be handled by the data-type `:int` and expose some
helper methods on the model:

```ruby
class Blog
  include CassandraKit::Record

  key :subdomain, :text
  column :name, :text
  column :status, :enum, values: { open: 1, closed: 2 }
end

blog = Blog.new(status: :open)
blog.open? # true
blog.closed? # false
blog.status # :open

Blog.status # { open: 1, closed: 2 }
```

### Schema synchronization ###

CassandraKit will automatically synchronize the schema stored in Cassandra to match
the schema you have defined in your models. If you're using Rails, you can
synchronize your schemas for everything in `app/models` by invoking:

```bash
rake cassandra_kit:migrate
```

### Record sets ###

Record sets are lazy-loaded collections of records that correspond to a
particular CQL query. They behave similarly to ActiveRecord scopes:

```ruby
Post.select(:id, :title).reverse.limit(10)
```

To scope a record set to a primary key value, use the `[]` operator. This will
define a scoped value for the first unscoped primary key in the record set:

```ruby
Post['bigdata'] # scopes posts with blog_subdomain="bigdata"
```

You can pass multiple arguments to the `[]` operator, which will generate an
`IN` query:

```ruby
Post['bigdata', 'nosql'] # scopes posts with blog_subdomain IN ("bigdata", "nosql")
```

To select ranges of data, use `before`, `after`, `from`, `upto`, and `in`. Like
the `[]` operator, these methods operate on the first unscoped primary key:

```ruby
Post['bigdata'].after(last_id) # scopes posts with blog_subdomain="bigdata" and id > last_id
```

You can also use `where` to scope to primary key columns, but a primary key
column can only be scoped if all the columns that come before it are also
scoped:

```ruby
Post.where(blog_subdomain: 'bigdata') # this is fine
Post.where(blog_subdomain: 'bigdata', permalink: 'cassandra') # also fine
Post.where(blog_subdomain: 'bigdata').where(permalink: 'cassandra') # also fine
Post.where(permalink: 'cassandra') # bad: can't use permalink without blog_subdomain
```

Note that record sets always load records in batches; Cassandra does not support
result sets of unbounded size. This process is transparent to you but you'll see
multiple queries in your logs if you're iterating over a huge result set.

#### Time UUID Queries ####

CQL has [special handling for the `timeuuid`
type](https://docs.datastax.com/en/cql/3.3/cql/cql_reference/uuid_type_r.html),
which allows you to return a rows whose UUID keys correspond to a range of
timestamps.

CassandraKit automatically constructs timeuuid range queries if you pass a `Time`
value for a range over a `timeuuid` column. So, if you want to get the posts
from the last day, you can run:

```ruby
Blog['myblog'].posts.from(1.day.ago)
```

### Updating records ###

When you update an existing record, CassandraKit will only write statements to the
database that correspond to explicit modifications you've made to the record in
memory. So, in this situation:

```ruby
@post = Blog.find(current_subdomain).posts.find(params[:id])
@post.update_attributes!(title: "Announcing CassandraKit 1.0")
```

CassandraKit will only update the title column. Note that this is not full dirty
tracking; simply setting the title on the record will signal to CassandraKit that you
want to write that attribute to the database, regardless of its previous value.

### Unloaded models ###

In the above example, we call the familiar `find` method to load a blog and then
one of its posts, but we didn't actually do anything with the data in the Blog
model; it was simply a convenient object-oriented way to get a handle to the
blog's posts. CassandraKit supports unloaded models via the `[]` operator; this will
return an **unloaded** blog instance, which knows the value of its primary key,
but does not read the row from the database. So, we can refactor the example to
be a bit more efficient:

```ruby
class PostsController < ActionController::Base
  def show
    @post = Blog[current_subdomain].posts.find(params[:id])
  end
end
```

If you attempt to access a data attribute on an unloaded class, it will
lazy-load the row from the database and become a normal loaded instance.

You can generate a collection of unloaded instances by passing multiple
arguments to `[]`:

```ruby
class BlogsController < ActionController::Base
  def recommended
    @blogs = Blog['cassandra', 'nosql']
  end
end
```

The above will not generate a CQL query, but when you access a property on any
of the unloaded `Blog` instances, CassandraKit will load data for all of them with
a single query. Note that CQL does not allow selecting collection columns when
loading multiple records by primary key; only scalar columns will be loaded.

There is another use for unloaded instances: you may set attributes on an
unloaded instance and call `save` without ever actually reading the row from
Cassandra. Because Cassandra is optimized for writing data, this "write without
reading" pattern gives you maximum efficiency, particularly if you are updating
a large number of records.

### Collection columns ###

Cassandra supports three types of collection columns: lists, sets, and maps.
Collection columns can be manipulated using atomic collection mutation; e.g.,
you can add an element to a set without knowing the existing elements.
CassandraKit
supports this by exposing collection objects that keep track of their
modifications, and which then persist those modifications to Cassandra on save.

Let's add a category set to our post model:


```ruby
class Post
  include CassandraKit::Record

  belongs_to :blog
  key :id, :uuid
  column :title, :text
  column :body, :text
  set :categories, :text
end
```

If we were to then update a post like so:

```ruby
@post = Blog[current_subdomain].posts[params[:id]]
@post.categories << 'Kittens'
@post.save!
```

CassandraKit would send the CQL equivalent of "Add the category 'Kittens' to the post
at the given `(blog_subdomain, id)`", without ever reading the saved value of
the `categories` set.

### Secondary indexes ###

Cassandra supports secondary indexes, although with notable restrictions:

* Only scalar data columns can be indexed; key columns and collection columns
  cannot.
* A secondary index consists of exactly one column.
* Though you can have more than one secondary index on a table, you can only use
  one in any given query.

CassandraKit supports the `:index` option to add secondary indexes to column
definitions:

```ruby
class Post
  include CassandraKit::Record

  belongs_to :blog
  key :id, :uuid
  column :title, :text
  column :body, :text
  column :author_id, :uuid, :index => true
  set :categories, :text
end
```

Defining a column with a secondary index adds several "magic methods" for using
the index:

```ruby
Post.with_author_id(id) # returns a record set scoped to that author_id
Post.find_by_author_id(id) # returns the first post with that author_id
Post.find_all_by_author_id(id) # returns an array of all posts with that author_id
```

You can also call the `where` method directly on record sets:

```ruby
Post.where(author_id: id)
```

### Consistency tuning ###

Cassandra supports [tunable
consistency](http://www.datastax.com/documentation/cassandra/2.0/cassandra/dml/dml_config_consistency_c.html),
allowing you to choose the right balance between query speed and consistent
reads and writes. CassandraKit supports consistency tuning for reads and writes:

```ruby
Post.new(id: 1, title: 'First post!').save!(consistency: :all)

Post.consistency(:one).find_each { |post| puts post.title }
```

Both read and write consistency default to `QUORUM`.

### Compression ###

Cassandra supports [frame compression](http://datastax.github.io/ruby-driver/features/#compression),
which can give you a performance boost if your requests or responses are big. To enable it you can
specify `client_compression` to use in cassandra_kit.yaml.

```yaml
development:
  host: '127.0.0.1'
  port: 9042
  keyspace: Blog
  client_compression: :lz4
```

### ActiveModel Support ###

CassandraKit supports ActiveModel functionality, such as callbacks, validations,
dirty attribute tracking, naming, and serialization. If you're using Rails 3,
mass-assignment protection works as usual, and in Rails 4, strong parameters are
treated correctly. So we can add some extra ActiveModel goodness to our post
model:

```ruby
class Post
  include CassandraKit::Record

  belongs_to :blog
  key :id, :uuid
  column :title, :text
  column :body, :text

  validates :body, presence: true

  after_save :notify_followers
end
```

Note that validations or callbacks that need to read data attributes will cause
unloaded models to load their row during the course of the save operation, so if
you are following a write-without-reading pattern, you will need to be careful.

Dirty attribute tracking is only enabled on loaded models.

### CQL Gotchas ###

CQL is designed to be immediately familiar to those of us who are used to
working with SQL, which is all of us. CassandraKit advances this spirit by providing
an ActiveRecord-like mapping for CQL. However, Cassandra is very much not a
relational database, so some behaviors can come as a surprise. Here's an
overview.

#### Upserts ####

Perhaps the most surprising fact about CQL is that `INSERT` and `UPDATE` are
essentially the same thing: both simply persist the given column data at the
given key(s). So, you may think you are creating a new record, but in fact
you're overwriting data at an existing record:

``` ruby
# I'm just creating a blog here.
blog1 = Blog.create!(
  subdomain: 'big-data',
  name: 'Big Data',
  description: 'A blog about all things big data')

# And another new blog.
blog2 = Blog.create!(
  subdomain: 'big-data',
  name: 'The Big Data Blog')
```

Living in a relational world, we'd expect the second statement to throw an
error because the row with key 'big-data' already exists. But not Cassandra: the
above code will just overwrite the `name` in that row.  Note that the
`description` will not be touched by the second statement; upserts only work on
the columns that are given.

#### Counting ####

Counting is not the same as in a RDB, as it can have a much longer runtime and
can put unexpected load on your cluster. As a result CassandraKit does not support
this feature. It is still possible to execute raw cql to get the counts, should
you require this functionality.
`MyModel.connection.execute('select count(*) from table_name;').first['count']`

## Compatibility ##

### Rails ###
* 6.1
* 6.0
* 5.2
* 5.1
* 5.0
* 4.2
* 4.1
* 4.0

### Ruby ###

* Ruby 2.5, 2,4, 2.3, 2.2, 2.1, 2.0

### Cassandra ###

* 2.1.x
* 2.2.x
* 3.0.x

## Running locally

This gem requires Ruby 2.5.1

```
RUBY_CFLAGS=-DUSE_FFI_CLOSURE_ALLOC rbenv install 2.5.1
gem install bundler -v 2.3.26 
bundle install

bundle exec rake test
```

## License ##

CassandraKit is distributed under the MIT license. See the attached LICENSE for all
the sordid details.

[CQL3]: http://docs.datastax.com/en/cql/3.3/cql/cqlIntro.html
