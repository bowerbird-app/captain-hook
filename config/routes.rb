# frozen_string_literal: true

CaptainHook::Engine.routes.draw do
  # Public incoming webhook endpoint
  post ":provider/:token", to: "incoming#create", as: :incoming_webhook

  # Admin interface
  namespace :admin do
    resources :incoming_events, only: %i[index show]
    resources :outgoing_events, only: %i[index show]

    root to: "incoming_events#index"
  end

  # Root redirects to admin
  root to: redirect("/captain_hook/admin")
end
