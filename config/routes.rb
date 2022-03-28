require 'sidekiq/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq" # TODO password protect

  namespace :api, :defaults => {:format => :json} do
    namespace :v1 do
      resources :registries, only: [:index] do
        resources :packages, only: [:index, :show] do 
          resources :versions, only: [:index]
        end
      end
    end
  end
end
