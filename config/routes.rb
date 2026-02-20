require 'sidekiq/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'
  
  resources :github_events, only: [:index, :show] do
    member do
      get :raw_payload
    end
    collection do
      post :fetch
    end
  end

  resources :push_events, only: [:index, :show]
end