# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "statisfy"
  s.version     = "0.0.9"
  s.required_ruby_version = ">= 3.2.0"
  s.date        = "2023-12-13"
  s.summary     = "A performant and flexible counter solution"
  s.description = "A performant and flexible counter solution that allows to make statistics on your models"
  s.authors     = ["Michaël Villeneuve"]
  s.homepage    = "https://github.com/Michaelvilleneuve/statisfy"
  s.email       = "contact@michaelvilleneuve.fr"
  s.files       = Dir["lib/**/*"]
  s.license     = "MIT"
  s.add_development_dependency "activerecord", "~> 7.0.4.3"
  s.add_development_dependency "activesupport", "~> 7.0.4.3"
  s.add_development_dependency "pry", "~> 0.14.1"
  s.add_development_dependency "redis", "~> 4.8.1"
  s.add_development_dependency "redis-client", "~> 0.17.0"
  s.add_development_dependency "rubocop", "~> 1.49.0"
  s.add_development_dependency "sqlite3", "~> 1.6.9"
end
