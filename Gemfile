source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.0"

gem "rails", "~> 7.0.4"
gem "sprockets-rails"
gem "pg", "~> 1.4"
gem "puma", "~> 6.0"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]
gem "bootsnap", require: false
gem "sassc-rails"
gem "counter_culture"
gem "faraday"
gem "faraday-retry"
gem "faraday-follow_redirects"
gem "nokogiri", "1.14.0.rc1"
gem "oj"
gem "ox"
gem "simple-rss"
gem "hiredis"
gem "redis", '< 5', require: ["redis", "redis/connection/hiredis"]
gem "sidekiq", '<7'
gem "sidekiq-unique-jobs"
gem "bibliothecary", github: "ecosyste-ms/bibliothecary", branch: "main"
gem "pagy"
gem "pghero"
gem "pg_query"
gem 'bootstrap'
gem "rack-attack"
gem "rack-attack-rate-limit", require: "rack/attack/rate-limit"
gem 'rack-cors'
gem 'rswag-api'
gem 'rswag-ui'
gem 'spdx', '2.0.12'
gem "semantic"
gem "semantic_range"
gem "sanitize-url"
gem "toml-rb"
gem "bugsnag"
gem "chartkick"
gem "groupdate"
gem 'jquery-rails'
gem 'addressable'
gem 'google-protobuf'
gem "xmlrpc"
gem 'rexml'
gem 'appsignal'
gem 'faraday-typhoeus'
gem 'packageurl-ruby'

group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
end

group :development do
  gem "web-console"
end

group :test do
  gem "shoulda"
  gem "webmock"
  gem "mocha"
  gem "rails-controller-testing"
end
