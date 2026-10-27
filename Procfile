web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
counts: bundle exec sidekiq -C config/sidekiq_counts.yml
release: bundle exec rake db:migrate
