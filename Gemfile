# frozen_string_literal: true

source 'http://rubygems.org'

# git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem 'activesupport'
gem 'octokit'

# there are some gems we use for testing the codebase -- not needed for actual use of the library
group :test do
  gem 'coveralls_reborn', '~> 0.20.0', require: false
  gem 'rake'
  gem 'rspec'
  gem 'rubocop', '1.11.0'
  gem 'simplecov-console'
  gem 'simplecov-lcov'
end

group :docs do
  gem 'yard'
end
