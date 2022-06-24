require 'sidekiq/web'

Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])) &
    ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"]))
end if Rails.env.production?

Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/docs'
  mount Rswag::Api::Engine => '/docs'
  
  mount Sidekiq::Web => "/sidekiq"
  mount PgHero::Engine, at: "pghero"

  namespace :api, :defaults => {:format => :json} do
    namespace :v1 do
      resources :registries, constraints: { id: /.*/ }, only: [:index, :show] do
        resources :packages, constraints: { id: /.*/ }, only: [:index, :show] do 
          resources :versions, only: [:index, :show], constraints: { id: /.*/ }
        end

        member do
          get :versions, to: 'versions#recent'
          get :package_names, to: 'packages#names', as: :package_names
        end
      end
    end
  end

  resources :registries, constraints: { id: /.*/ }, only: [:index, :show] do
    resources :packages, constraints: { id: /.*/ }, only: [:index, :show] do 
      resources :versions, only: [:index, :show], constraints: { id: /.*/ }
    end

    member do
      get :versions, to: 'versions#recent'
    end
  end

  root "home#index"
end
