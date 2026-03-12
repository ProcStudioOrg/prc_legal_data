# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # Rotas de advogados
      get 'lawyer/:oab', to: 'lawyers#show_by_oab'
      post 'lawyer/create', to: 'lawyers#create_lawyer'
      post 'lawyer/:oab/update', to: 'lawyers#update_lawyer'
      post 'lawyer/:oab/crm', to: 'lawyers#update_crm'
      get 'lawyer/:oab/debug', to: 'lawyers#_debug'
      get 'lawyer/state/:state/last', to: 'lawyers#last_oab_by_state'

      # Rotas de sociedades
      post 'society/create', to: 'societies#create_society'
      get 'society/:inscricao', to: 'societies#show'
      post 'society/:inscricao/update', to: 'societies#update_society'
      delete 'society/:inscricao', to: 'societies#destroy'

      # Rotas de relações advogado-sociedade
      resources :lawyer_societies, only: [:create, :show, :update, :destroy]

      # Autenticação para obter API key
      post 'auth/login', to: 'authentication#login'
    end
  end

  namespace :admin do
    get 'dashboard', to: 'dashboard#index'
    resources :api_keys
  end
end
