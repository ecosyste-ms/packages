source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.1"

gem "rails", "~> 7.0.2", ">= 7.0.2.3"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", "~> 5.6"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]
gem "bootsnap", require: false
gem "sassc-rails"
gem "counter_culture"
gem "faraday"
gem "faraday-retry"
gem "faraday-gzip"
gem "faraday-follow_redirects"
gem "nokogiri"
gem "oj"
gem "ox"
gem "simple-rss"
gem "sidekiq"
gem "sidekiq-unique-jobs"
gem "sidekiq-scheduler"
gem "bibliothecary"
gem "pagy"

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
