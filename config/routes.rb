require 'sidekiq/web'

Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])) &
    ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"]))
end if Rails.env.production?

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq" # TODO password protect
  mount PgHero::Engine, at: "pghero" # TODO password protect

  namespace :api, :defaults => {:format => :json} do
    namespace :v1 do
      resources :registries, only: [:index] do
        resources :packages, only: [:index, :show] do 
          resources :versions, only: [:index]
        end
      end
    end
  end

  root "home#index"
end
