require "sidekiq/throttled"

Rails.application.config.to_prepare do
  Sidekiq::Throttled::Registry.add(
    :registry_host,
    threshold: {
      limit: ->(registry_id, *) { Registry.rate_limit_for(registry_id) },
      period: 1.second,
      key_suffix: ->(registry_id, *) { (Registry.host_for(registry_id) || registry_id).to_s }
    }
  )
end
