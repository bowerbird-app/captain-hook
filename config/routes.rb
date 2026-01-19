# frozen_string_literal: true

CaptainHook::Engine.routes.draw do
  # Admin interface (must come BEFORE wildcard routes)
  namespace :admin do
    resources :providers do
      resources :actions, only: %i[index show edit update destroy]
    end
    resources :incoming_events, only: %i[index show]

    # Sandbox for testing webhooks (dry run)
    get "sandbox", to: "sandbox#index"
    post "sandbox/test", to: "sandbox#test_webhook"

    root to: "providers#index"
  end

  # Root redirects to admin
  root to: redirect("/captain_hook/admin")

  # Public incoming webhook endpoint (must come AFTER admin routes)
  post ":provider/:token", to: "incoming#create", as: :incoming_webhook
end
