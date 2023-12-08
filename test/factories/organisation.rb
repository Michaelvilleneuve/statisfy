require "active_record"

class Organisation < ActiveRecord::Base
  has_many :users
end