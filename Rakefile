# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"
require "rake/testtask"

RuboCop::RakeTask.new

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/**.rb"]
end

desc "Run tests"
task default: :test