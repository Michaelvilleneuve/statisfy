# Statisfy

[![Build](https://github.com/Michaelvilleneuve/statisfy/actions/workflows/main.yml/badge.svg)](https://github.com/Michaelvilleneuve/statisfy/actions)
[![Gem Version](https://badge.fury.io/rb/statisfy.svg)](https://badge.fury.io/rb/statisfy)

This gem allows you to easily create performant statistics for your ActiveRecord models without having to write and run complex SQL queries.

By leveraging the power of Redis, Statisfy elegantly manages counters in the background so that you can use them with ease. 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'statisfy'
```

Execute

```bash
$ bundle install
```

Then add the following to a `config/initializers/statisfy.rb` file:

```ruby
Statisfy.configure do |config|
  # This is the Redis client that will be used to store counters
  config.redis_client = Redis.new

  # If you want to use Sidekiq to update counters in the background
  # This is optional, but recommended for performance reasons
  # Anything you add to this block will be executed in the context of the
  # Sidekiq worker that updates the counters
  #
  config.append_to_counters = ->(_) { include Sidekiq::Worker }

  # This allows you to define the default scopes for your counters
  # This is simply to avoid having to define the same scopes over and over
  # again for each counter
  config.default_scopes = -> { [subject.organisation, subject.department] }
end

# The following is important because it ensures that all counters are loaded
# and can start listening events without having to require them manually.
Rails.application.config.after_initialize do

  # You can put your counters anywhere you want, as long as they are loaded
  Dir[Rails.root.join("app/stats/counters/**/*.rb")].each { |file| require file }
end
```
## Simple usage

### Basic counter

This will simply increment the counter every time a `User` is created.

```ruby
# Define a class, and include the Statisfy::Counter module
# You can put this class anywhere you want, as long as it is loaded by the initializer
# See the Installation section for more details
class UsersCreated
  include Statisfy::Counter

  count every: :user_created
end

# Anytime a user is created, the counter will be incremented
User.create(name: "John Doe")

# And then get the count like this:
UsersCreated.value
# => 1

# You can also get the count for a specific month
UsersCreated.value(month: Time.now)

# Or get a graph of values grouped by month
# By default it returns the last 24 months
UsersCreated.values_grouped_by_month(stop_at: Time.now.last_month.end_of_month, start_at: Time.now.last_year)
# => 
# {
#   "2023/01", value: 766,
#   "2023/02", value: 1246,
#   ... 
# }
```

If you prefer you can also `include Statisfy::Model` in your model and define the counter directly on the model.
In this case you'll have to prefix APIs with `statisfy_` to avoid conflicts with ActiveRecord methods.

You'll also need to specify the `:as` option to give a name to your counter which will be used to access the value.

```ruby
class User < ApplicationRecord
  include Statisfy::Model

  statisfy_count every: :user_created, as: :number_of_users_created
  statisfy_aggregate every: :user_update, as: :average_salary, value: -> { salary }
end

User.create(name: "John Doe", salary: 1000)
User.create(name: "John Troe", salary: 2000)

# And then get the count like this:
User.number_of_users_created.value
# => 2

User.average_salary.value
# => 1500
```


### Scoped counter

Imagine you have a `User` model that belongs to an `Organisation` and you want to count the number of users created per organisation.

```ruby
class UsersCreated
  include Statisfy::Counter

  count every: :user_created,
        scopes: -> { [user.organisation] }
end

# This will increment the counter for the organisation of the user (and also the global one)
User.create(name: "John Doe", organisation: Organisation.first)

# And then get the count like this:
UsersCreated.value(scope: Organisation.first)
# => 1

# Or get a graph of values grouped by month
UsersCreated.values_grouped_by_month(scope: Organisation.first)
```

### Aggregation based statistics

This is useful when you want to get an average or sum of a value.

```ruby
class AverageUserSalary
  include Statisfy::Aggregate

  aggregate every: :user_created,
            value: -> { user.salary }
end

User.create(name: "John Doe", salary: 1000)
User.create(name: "Jane Doe", salary: 2000)


# This will return the average salary of all users
AverageUserSalary.value
# => 1500

# This will return the sum of all salaries
AverageUserSalary.sum
# => 3000

# You can also get the average salary for a specific month, scope, etc
AverageUserSalary.value(month: Time.now, scope: Organisation.first)
```

## API

### count

This method is used to define a counter.

> Note that every `lambda` option is executed in the context of the counter instance. You can access the model instance under the model instance name. For instance `user` for a `User` model.


| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `every`    | Array<symbols>        | The event(s) that will trigger the counter. `model_(created/updated/destroyed)`. The model is deduced from the event name. `:user_created` will catch every `User.create!` |
| `scopes`   | lambda, optional | Array of scopes to take into account. For instance, if a model `Post` has_many `authors`, then setting `-> { post.authors }` will tell you how many authors wrote a post |
| `if`      | lambda, optional | Boolean. If it returns false, the counter will not be incremented. You have access to your instance `.previous_changes` which allows you to increment only upon certain changes. |
| `if_async` | lambda, optional | Boolean. Similar to `if`, but executed asynchronously. Allows to not slow down `INSERT` or `UPDATE` statements. Useful if your `if` calls complex model relationships |
| `decrement_if` | lambda, optional | Boolean. If it returns true, then the counter will be decremented instead of incremented |
| `uniq_by` | lambda, optional | Won't count the same value twice. By default it is uniq on the `id`. Example use case: if a `Post` is written by an `author_id`, you could set `-> { post.author_id}` to know how many authors wrote an article this month |
| `decrement_on_destroy` | Boolean, optional | Default is true. The counter will be decremented when the model instance is destroyed. |
| `date_override` | DateTime, optional | Default is `instance.created_at`. |

### aggregate

This method is used to define an aggregate counter.
> Note that every `lambda` option is executed in the context of the counter instance. You can access the model instance under the model instance name. For instance `user` for a `User` model.

> An aggregate counter has the same options as a basic counter, but also has the following options:

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `value`    | lambda        | The value to aggregate that will be used to compute the average or sum.  |


## Class methods

### .values_grouped_by_month

This method returns a hash containing the months and the values of the counter for that month.
If you want to use this method outside of a counter, you can include `include Statisfy::Monthly` which contains this method only.


| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | Object, optional     | The scope of the counter. See scope option above |
| `start_at` | Date, optional| The date from which you want to start counting. If not provided, counts from the beginning. |
| `stop_at`  | Date, optional| The date at which you want to stop counting. If not provided, counts up to the current date. |

Returns 

```ruby
{
  "2023/01", value: 766,
  "2023/02", value: 1246,
  ...
}
```

### .value

This method returns the value of the counter.

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | ActiveRecord instance, optional | The scope of the counter. See scope option above |
| `month`    | Date, optional| The month for which you want to get the value. If not provided, returns the value for the current month. |

### .sum

This method returns the sum of the values of the counter.
/!\ This method is only available for counters that use the `Statisfy::Aggregate` module.

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | ActiveRecord instance, optional | The scope of the counter. See scope option above |
| `month`    | Date, optional| The month for which you want to get the value. If not provided, returns the value for the current month. |

### .average

This method returns the average of the values of the counter.
/!\ This method is only available for counters that use the `Statisfy::Aggregate` module.

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | ActiveRecord instance, optional | The scope of the counter. See scope option above |
| `month`    | Date, optional| The month for which you want to get the value. If not provided, returns the value for the current month. |

## Initializing a counter

If you want to count on a model with existing data, you'll need to initialize the counter.
Initializing a counter is done by manually triggering an increment of counters. Basically it's a matter of doing this:

```ruby
# Given a User class
class User < ActiveRecord::Base
end

# And a counter
class UsersCreated
  include Statisfy::Counter

  count every: :user_created
end

# You can initialize the counter like this
User.all.find_each do |user|
  UsersCreated.trigger_with(user)
end
```

Users created in the meantime and in the future will be automatically counted anyway.

### Initializing scoped counters

If your data is scoped with some of your model associations, don't forget to include the associated models to speed up the initialization:

```ruby
class User < ActiveRecord::Base
  belongs_to :organisation
  belongs_to :department
end

class UsersCreated
  include Statisfy::Counter

  count every: :user_created,
        scopes: -> { [user.organisation, user.department] }
end

User.all.includes(:organisation, :department).find_each do |user|
  UsersCreated.trigger_with(user)
end
```

### Initializing counters with conditions

If you need to increment only some instances, the `if` option of your counter will automatically bypass the instances not matching the condition.

But if your counter requires conditions only present during updates, like coming from `.previous_changes`, since this data is not available during initialization, you'll need to add that condition to the request manually, and also skip validations.

For instance, consider the following counter:
```ruby
class NumberOfActiveUsers
  include Statisfy::Counter

  count every: :user_created,
        if: -> { user.previous_changes[:status].present? && user.status == "active" }
end
```

You'll need to initialize the counter like this:

```ruby
# Retrieve all users matching the condition
User.where(status: "active").find_each do |user|
  # Skip validations to avoid running the `if` condition
  # This is safe because we know that all given users match the condition
  NumberOfActiveUsers.trigger_with(user, skip_validation: true)
end
```

## Development

After checking out the repo, run `bundle` and the `bundle rake` to run the test suite.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Michaelvilleneuve/statisfy.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
