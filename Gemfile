source 'https://rubygems.org'
ruby '~> 2.5'

gemspec

gem 'require_all'

gem 'rake'

gem 'activesupport'

gem 'ai4r'

group :development, :test do
  gem 'benchmark-ips' # to in-place benchmark of different implementations
  gem 'byebug'

  # For linting and offline code analysis
  gem 'rubocop'
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'solargraph'

  # For creating dependency graphs
  # gem 'rubrowser'
end

group :test do
  gem 'minitest'
  gem 'minitest-around' # to create a block around unit tests for initialisation and cleanup
  gem 'minitest-bisect' # to identify randomly failing order-depoendent tests
  gem 'minitest-focus'
  gem 'minitest-reporters'
  gem 'minitest-retry'
  gem 'minitest-stub_any_instance'
  gem 'simplecov', require: false
end
