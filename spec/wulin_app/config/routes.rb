# frozen_string_literal: true

Rails.application.routes.draw do
  resources :people
  root to: 'homepage#index'
end
