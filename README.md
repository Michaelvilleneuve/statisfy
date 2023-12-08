# Statisfy

[![Build](https://github.com/Michaelvilleneuve/statisfy/actions/workflows/main.yml/badge.svg)](https://github.com/Michaelvilleneuve/statisfy/actions)
[![Gem Version](https://badge.fury.io/rb/statisfy.svg)](https://badge.fury.io/rb/statisfy)

This gem allows you to easily create performant statistics for your ActiveRecord models without having to write and run complex SQL queries.

By leveraging the power of Redis, Statisfy elegantly manages counters so that you can use them with ease. 

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

### Defining a simple counter

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

### Defining a counter with a scope

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

### Defining an aggregation based stat

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

## `count` method

This method is used to define a counter.

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `every`    | Array<:#{model_name}_(created|updated|destroyed)>        | The event(s) that will trigger the counter. Note that the model is deduced from the event name. For instance :user_created will catch every `User.create!`. :user_destroyed will catch every `user.destroy!` |
| `scopes`   | lambda | This proc should return an array of scopes to take into account. For instance, if a model `Post` has many `authors`, then `-> { post.authors }` would allow you to know the # of post that each author wrote. It is executed as a counter instance. You'll have access to the model instance under the model instance name. For instance `user` for a `User` model.  |
| `if`      | lambda, optional | This proc should return a boolean. If it returns false, the counter will not be incremented. Here you have access to your instance `.previous_changes` which allows you to increment only upon certain changes. This proc is executed as a counter instance. You'll have access to the model instance under the model instance name. For instance `user` for a `User` model. |
| `if_async` | lambda, optional | Similar to `if` option, but executed asynchronously, this allows to avoid slowing down `INSERT` and `UPDATE` statements. This is useful when you `if` calls complex model relationships |
| `decrement_if` | lambda, optional | This proc should return a boolean. If it returns true, then the counter will be decremented instead of incremented. This proc is executed as a counter instance. You'll have access to the model instance under the model instance name. For instance `user` for a `User` model. |
| `uniq_by` | lambda, optional | This allows you to avoid counting multiple times the same model instance. By default it is uniq on the `id`. Example : if you have a `Post` model that is writter by an `author_id`, you could set `-> { post.author_id}` to know how many authors wrote an article this month. |


## Class methods

### .values_grouped_by_month

This method returns a hash containing the months and the values of the counter for that month.
If you want to use this method outside of a counter, you can include `include Statisfy::Monthly` which contains this method only.


| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | Object        | The scope of the counter, which can be an Organisation or a Department. |
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
| `scope`    | Object        | The scope of the counter, which can be an Organisation or a Department. |
| `month`    | Date, optional| The month for which you want to get the value. If not provided, returns the value for the current month. |

### .sum

This method returns the sum of the values of the counter.
/!\ This method is only available for counters that use the `Statisfy::Aggregate` module.

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | Object        | The scope of the counter, which can be an Organisation or a Department. |
| `month`    | Date, optional| The month for which you want to get the value. If not provided, returns the value for the current month. |

### .average

This method returns the average of the values of the counter.
/!\ This method is only available for counters that use the `Statisfy::Aggregate` module.

| Parameter  | Type          | Description                                                 |
|------------|---------------|-------------------------------------------------------------|
| `scope`    | Object        | The scope of the counter, which can be an Organisation or a Department. |
| `month`    | Date, optional| The month for which you want to get the value. If not provided, returns the value for the current month. |

## Development

After checking out the repo, run `bundle` and the `bundle rake` to run the test suite.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Michaelvilleneuve/statisfy.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
