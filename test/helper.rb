require "active_record"
require "redis"
require "statisfy"

ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

ActiveRecord::Base.connection.create_table :users, force: true do |t|
  t.string(:name)
  t.integer(:organisation_id)
  t.integer(:salary)
  t.timestamps
end

ActiveRecord::Base.connection.create_table :organisations, force: true do |t|
  t.string(:name)
  t.timestamps
end

Statisfy.configure do |config|
  config.redis_client = Redis.new
end
