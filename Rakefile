require 'rubygems'
require 'bundler/setup'
require 'rakeup'

require 'rake/testtask'
Rake::TestTask.new do |t|
  ENV['APP_ENV'] ||= 'test'
  t.pattern = 'test/**/*_test.rb'
end
