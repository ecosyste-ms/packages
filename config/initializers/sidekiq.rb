SidekiqUniqueJobs.configure do |config|
  config.reaper          = :ruby
  config.reaper_count    = 2_000
  config.reaper_interval = 60
  config.reaper_timeout  = 15

  config.reaper_resurrector_enabled  = true
  config.reaper_resurrector_interval = 300
end

Sidekiq.configure_server do |config|
  config.redis = { ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end

  SidekiqUniqueJobs::Server.configure(config)
end

Sidekiq.configure_client do |config|
  config.logger = Rails.logger if Rails.env.test?
  config.redis = { ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end
end