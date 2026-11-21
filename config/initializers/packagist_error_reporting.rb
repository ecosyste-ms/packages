require_relative '../../lib/packagist_error_reporting'

Rails.application.config.after_initialize do
  if Appsignal.config[:enable_rails_error_reporter]
    Appsignal::Integrations::RailsErrorReporterSubscriber.singleton_class.prepend(PackagistErrorReporting)
  end
end

Sidekiq.configure_server do |config|
  config.death_handlers << PackagistErrorReporting.method(:retries_exhausted)
end
