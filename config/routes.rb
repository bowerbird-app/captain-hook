# frozen_string_literal: true

CaptainHook::Engine.routes.draw do
  # Public incoming webhook endpoint
  post ":provider/:token", to: "incoming#create", as: :incoming_webhook

  # Admin interface
  namespace :admin do
    resources :providers do
      resources :handlers, only: %i[index]
    end
    resources :incoming_events, only: %i[index show]

    root to: "providers#index"
  end

  # Root redirects to admin
  root to: redirect("/captain_hook/admin")
end
