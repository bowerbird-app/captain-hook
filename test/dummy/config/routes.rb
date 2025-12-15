Rails.application.routes.draw do
  # Mount the CaptainHook engine
  mount CaptainHook::Engine, at: "/captain_hook"

  # Mount MakeupArtist style guide
  mount MakeupArtist::Engine, at: "/makeup_artist"

  # Webhook Tester
  get "webhook_tester", to: "webhook_tester#index", as: :webhook_tester
  post "webhook_tester/send_incoming", to: "webhook_tester#send_incoming", as: :send_incoming_webhook_tester
  post "webhook_tester/send_outgoing", to: "webhook_tester#send_outgoing", as: :send_outgoing_webhook_tester

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root to: redirect("/captain_hook")
end
