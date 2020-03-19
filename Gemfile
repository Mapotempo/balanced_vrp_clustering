source 'https://rubygems.org'
ruby '~> 2.3'

gem 'require_all'

gem 'rack'
gem 'rack-cors'
gem 'rakeup'

# remove grape ??

gem 'grape', '<0.19.0' # TODO: Grape 1.2.4 reduces performances
gem 'grape-entity'
gem 'grape-swagger', '<0.26.0' # TODO: Waiting Grape 1+
gem 'grape-swagger-entity', '<0.1.6' # TODO: Waiting Grape 1+
gem 'grape_logging'

gem 'rack-contrib'
gem 'resque', '<2'
gem 'resque-status', '>0.4'

gem 'ai4r'
gem 'sim_annealing'

group :development, :test do
  gem 'benchmark-ips' # to in-place benchmark of different implementations
  gem 'byebug'

  # For linting and offline code analysis
  gem 'rubocop'
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'solargraph'

  # For creating dependency graphs
  gem 'rubrowser'

  ## Next gems to use the debuger of vscode directly
  ## but due to a bug in rubyide/vscode-ruby it doesn't
  ## work at the moment with rake::workers
  # gem 'psych', '<3.0.2' # TODO: Waiting Ruby 2.2
  # gem 'ruby-debug-ide'
  # gem 'debase'
end

group :test do
  gem 'minitest'
  gem 'minitest-around' # to create a block around unit tests for initialisation and cleanup
  gem 'minitest-bisect' # to identify randomly failing order-depoendent tests
  gem 'minitest-focus'
  gem 'minitest-reporters'
  gem 'minitest-stub_any_instance'
  gem 'rack-test'
  gem 'simplecov', require: false
end