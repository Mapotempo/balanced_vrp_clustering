require 'rubygems'
require 'bundler/setup'
require 'rakeup'
require 'resque/tasks'

RakeUp::ServerTask.new do |t|
  t.port = 1791
  t.pid_file = 'tmp/server.pid'
  t.server = :puma
end

require 'rake/testtask'
Rake::TestTask.new do |t|
  ENV['APP_ENV'] ||= 'test'
  t.pattern = 'test/**/*_test.rb'
end
