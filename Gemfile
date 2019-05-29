# frozen_string_literal: true

source 'http://rubygems.org'

# git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem 'activesupport'
gem 'octokit'

# there are some gems we use for testing the codebase -- not needed for actual use of the library
group :test do
  gem 'rake'
  gem 'coveralls', require: false
  gem 'rspec'
  gem 'rubocop'
  gem 'simplecov', require: false
  gem 'simplecov-console', require: false
end

group :docs do
  gem 'yard'
end
