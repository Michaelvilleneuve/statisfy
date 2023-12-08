require "active_record"
require_relative "organisation"

class User < ActiveRecord::Base
  belongs_to :organisation
end