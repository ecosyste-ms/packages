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
      resources :dependencies, only: [:index]

      resources :keywords, only: [:index, :show], constraints: { id: /.*/ }

      resources :packages, only: [:lookup] do
        collection do
          get :lookup, to: 'packages#lookup'
          get :ping, to: 'packages#ping_all'
        end
      end

      resources :registries, constraints: { id: /[^\/]+/  }, only: [:index, :show] do
        resources :maintainers, only: [:index, :show], constraints: { id: /.*/ } do
          member do
            get :packages
          end
        end

        resources :namespaces, only: [:index, :show], constraints: { id: /.*/ } do
          member do
            get :packages
          end
        end

        resources :packages, constraints: { id: /.*/ }, only: [:index, :show] do 
          resources :versions, only: [:index, :show], constraints: { id: /.*/ }
          member do
            get :dependent_packages, to: 'packages#dependent_packages'
            get :related_packages, to: 'packages#related_packages'
            get :ping, to: 'packages#ping'
            get :version_numbers, to: 'versions#version_numbers'
          end
        end

        member do
          get :versions, to: 'versions#recent'
          get :package_names, to: 'packages#names', as: :package_names
        end
      end
    end
  end

  get :top, to: 'top#index'
  get 'top/:ecosystem', to: 'top#ecosystem', as: :top_ecosystem

  resources :ecosystems, only: [:index, :show], constraints: { id: /.*/ }

  resources :registries, constraints: { id: /[^\/]+/  }, only: [:index, :show], :defaults => {:format => :html} do
    resources :maintainers, only: [:index, :show], constraints: { id: /.*/ } do
      member do
        get :namespaces, to: 'maintainers#namespaces'
      end
    end
    resources :namespaces, only: [:index, :show], constraints: { id: /.*/ } do
      member do
        get :maintainers, to: 'namespaces#maintainers'
      end
    end

    resources :packages, constraints: { id: /.*/ }, only: [:index, :show] do 
      resources :versions, only: [:index, :show], constraints: { id: /.*/ }
      collection do
        get :recent_versions_data, to: 'packages#recent_versions_data'
      end
      member do
        get :dependent_packages, to: 'packages#dependent_packages'
        get :maintainers, to: 'packages#maintainers'
        get :related_packages, to: 'packages#related_packages'
        get :advisories, to: 'packages#advisories'
      end
    end

    member do
      get :versions, to: 'versions#recent'
      get :keywords, to: 'registries#keywords', as: :keywords
      get 'keywords/:keyword', to: 'registries#keyword', as: :keyword, constraints: { keyword: /.*/ }
    end

    collection do
      get :status, to: 'registries#status'
    end
  end

  resources :keywords, only: [:index, :show], constraints: { id: /.*/ }

  get :funding, to: 'funding#index'
  get 'funding/:id', to: 'funding#show', as: :funding_registry, constraints: { id: /[^\/]+/  }

  get :underproduction, to: 'underproduction#index'
  get 'underproduction/:id', to: 'underproduction#show', as: :underproduction_registry, constraints: { id: /[^\/]+/  }

  get :infrastructure, to: 'infrastructure#index'
  
  get :unseen, to: 'unseen#index'
  get 'unseen/:ecosystem', to: 'unseen#ecosystem', as: :unseen_ecosystem

  get :recent_versions_data, to: 'home#recent_versions_data'

  resources :exports, only: [:index], path: 'open-data'

  get '/404', to: 'errors#not_found'
  get '/422', to: 'errors#unprocessable'
  get '/500', to: 'errors#internal'

  root "home#index"
end
