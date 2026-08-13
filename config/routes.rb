Rails.application.routes.draw do
  mount OpenehrRails::Engine => '/openehr'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get  "templates",         to: "templates#index"
  post "templates/preview", to: "templates#preview"
  post "templates",         to: "templates#create"

  get  "forms/:template_id",        to: "forms#show", as: :form,
       format: false, constraints: { template_id: /[^\/]+/ }
  post "compositions/:template_id", to: "compositions#create", as: :template_compositions,
       format: false, constraints: { template_id: /[^\/]+/ }
  get  "compositions",              to: "compositions#index"
  get  "compositions/:id",          to: "compositions#show", as: :composition

  root "templates#index"
end
