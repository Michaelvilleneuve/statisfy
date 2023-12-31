$VERBOSE = nil

require "minitest/autorun"
require "statisfy"
require "active_support"
require_relative "helper"

require_relative "factories/user"
require_relative "factories/organisation"

class StatisfyTest < ActiveSupport::TestCase
  setup do
    Redis.new.flushall
    User.delete_all
    Organisation.delete_all
  end

  test "it is a module" do
    assert_kind_of Module, Statisfy
  end

  test "it can count a resource" do
    class UserCounter
      include Statisfy::Counter

      count every: :user_created
    end

    User.create!
    assert UserCounter.value == 1
  end

  test "it can count a resource with a scope" do
    class UserCounter
      include Statisfy::Counter

      count every: :user_created, scopes: -> { [user.organisation] }
    end

    apple = Organisation.create!(name: "Apple")
    microsoft = Organisation.create!(name: "Microsoft")

    User.create!(name: "Steve", organisation: apple)
    User.create!(name: "Bill", organisation: microsoft)

    assert UserCounter.value(scope: apple) == 1
    assert UserCounter.value(scope: microsoft) == 1
    assert UserCounter.value == 2
  end

  test "it can count a resource with a scope and a month" do
    class UserCounter
      include Statisfy::Counter

      count every: :user_created, scopes: -> { [user.organisation] }
    end

    apple = Organisation.create!(name: "Apple")
    microsoft = Organisation.create!(name: "Microsoft")

    User.create!(name: "Steve", organisation: apple)
    User.create!(name: "Bill", organisation: microsoft)

    assert UserCounter.value(scope: apple, month: Date.today) == 1
    assert UserCounter.value(scope: microsoft, month: Date.today) == 1
    assert UserCounter.value(month: Date.today) == 2
  end

  test "#values_grouped_by_month creates a hash of values grouped by month" do
    class UserCounter
      include Statisfy::Counter

      count every: :user_created, scopes: -> { [user.organisation] }
    end

    25.times do |i|
      creation_date = (24 - i).months.ago.beginning_of_month
      between_2_and_5 = rand(2..5)
      
      between_2_and_5.times do
        User.create!(created_at: creation_date)
      end
    end

    assert UserCounter.values_grouped_by_month(stop_at: 1.month.ago).values.all? { |v| v >= 2 && v <= 5 }
  end

  test "if option prevents running counter" do
    class UserCounterFalse
      include Statisfy::Counter

      count every: :user_created, if: -> { false }
    end

    class UserCounter
      include Statisfy::Counter

      count every: :user_created, if: -> { true }
    end

    User.create!
    assert UserCounterFalse.value == 0
    assert UserCounter.value == 1
  end

  test "if_async option prevents running counter" do
    class UserCounterFalse
      include Statisfy::Counter

      count every: :user_created, if_async: -> { false }
    end

    class UserCounter
      include Statisfy::Counter

      count every: :user_created, if_async: -> { true }
    end

    User.create!
    assert UserCounterFalse.value == 0
    assert UserCounter.value == 1
  end

  test "uniq_by option allows to create group of values" do
    class NumberOfSteveCounter
      include Statisfy::Counter

      count every: :user_created, uniq_by: -> { user.name == "Steve" }
    end

    User.create!(name: "Steve")
    User.create!(name: "Steve")
    User.create!(name: "Bill")

    assert_equal NumberOfSteveCounter.value, 2
  end

  test "trigger_with option allows to initialize a counter when a table wasn't empty" do
    5.times { User.create! }
    class UserCreated
      include Statisfy::Counter

      count every: :user_created
    end
    
    User.find_each do |user|
      UserCreated.trigger_with(user)
    end

    assert_equal UserCreated.value, 5
  end

  test "trigger_with can skip if validations" do
    3.times { User.create!(name: "Steve") }
    2.times { User.create!(name: "Bill") }
    Redis.new.flushall

    class UserCreated
      include Statisfy::Counter

      count every: :user_updated, if: -> { user.previous_changes[:name] && user.name == "Steve" }
    end
    assert_equal UserCreated.value, 0
    
    User.where(name: "Steve").find_each do |user|
      UserCreated.trigger_with(user, skip_validation: false)
    end

    # Since previous_changes is missing when initializing, validation fails
    assert_equal UserCreated.value, 0

    User.where(name: "Steve").find_each do |user|
      UserCreated.trigger_with(user, skip_validation: true)
    end

    # Skipping validations allows to initialize the counter
    assert_equal UserCreated.value, 3
  end

  test "decrement_if option allows to decrement a counter" do
    paul = User.create!(name: "Paul")
    jean = User.create!(name: "Jean")
    marc = User.create!(name: "Marc")

    class SteveCounter
      include Statisfy::Counter

      count every: :user_updated,
            if: -> { user.previous_changes[:name] },
            decrement_if: -> { user.name != "Steve" }
    end

    paul.update!(name: "Steve")
    jean.update!(name: "Steve")
    marc.update!(name: "Steve")
    
    assert_equal SteveCounter.value, 3
    
    paul.update!(name: "Paul")
    jean.update!(name: "Jean")

    assert_equal SteveCounter.value, 1
  end

  test "aggregate option allows to aggregate instead of increment and get an average" do
    class SalaryPerUser
      include Statisfy::Aggregate

      aggregate every: :user_created, value: -> { user.salary }
    end

    User.create!(salary: 2000)
    User.create!(salary: 3000)
    User.create!(salary: 4000)

    assert_equal 3000, SalaryPerUser.average
    assert_equal 9000, SalaryPerUser.sum
  end

  test "decrement_on_destroy option allows to decrement a counter when a resource is destroyed" do
    class UserCounter
      include Statisfy::Counter

      count every: :user_created, decrement_on_destroy: true
    end

    User.create!
    assert_equal UserCounter.value, 1
    User.last.destroy
    assert_equal UserCounter.value, 0
  end

  test "decrement_on_destroy works with custom uniq uniq_by" do
    class OrganisationsWithUsersCounter
      include Statisfy::Counter

      count every: :user_created, decrement_on_destroy: true, uniq_by: -> { user.organisation_id }
    end

    User.create!(organisation_id: 8)
    User.create!(organisation_id: 8)
    User.create!(organisation_id: 2)

    assert_equal OrganisationsWithUsersCounter.value, 2
    User.where(organisation_id: 8).first.destroy
    assert_equal OrganisationsWithUsersCounter.value, 2
    User.where(organisation_id: 8).last.destroy
    assert_equal OrganisationsWithUsersCounter.value, 1
  end

  test "it can count on a model directly" do
    class ::User < ActiveRecord::Base
      include Statisfy::Model

      statisfy_count every: :user_created, as: :organisations_with_users, uniq_by: -> { user.organisation_id }
      statisfy_count every: :user_created, as: :number_of_users
      statisfy_aggregate every: :user_created, as: :average_salary, value: -> { user.salary }
    end

    User.create!(organisation_id: 8, salary: 2000)
    User.create!(organisation_id: 8, salary: 3000)
    User.create!(organisation_id: 2, salary: 4000)

    assert_equal User.number_of_users.value, 3
    assert_equal User.organisations_with_users.value, 2
    assert_equal User.average_salary.value, 3000
  end
end
