Rails.application.routes.draw do
  mount OpenehrRails::Engine => "/openehr"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # 患者（EHR）の一覧・作成・詳細（skoba/anlage#130、docs/design/m3-plan.md 7 節）。:id は ehr_id
  # いまの患者の選択と解除（skoba/anlage#134）。選んだ患者はセッションに持つ
  delete "patients/selection", to: "patients#deselect", as: :patient_selection
  resources :patients, only: %i[index create show] do
    post :select, on: :member
  end

  get  "templates",         to: "templates#index"
  post "templates/preview", to: "templates#preview"
  post "templates",         to: "templates#create"
  # テンプレートの詳細と版の履歴（skoba/anlage#98、docs/design/m3-plan.md 3 節）
  get  "templates/:template_id", to: "templates#show", as: :template,
       format: false, constraints: { template_id: /[^\/]+/ }
  # 2 つの版の差分（skoba/anlage#100）。?from=<版>&to=<版>
  get  "templates/:template_id/diff", to: "templates#diff", as: :template_diff,
       format: false, constraints: { template_id: /[^\/]+/ }
  get  "templates/:template_id/versions/:version", to: "templates#show", as: :template_version,
       format: false, constraints: { template_id: /[^\/]+/, version: /[^\/]+/ }

  get "pathcards/search", to: "pathcards#search"
  # クエリビルダー（docs/design/s2-query-builder-plan.md 6.4）。状態は URL のパラメータだけ
  get "queries/new", to: "queries#new", as: :new_query

  get  "forms/:template_id",        to: "forms#show", as: :form,
       format: false, constraints: { template_id: /[^\/]+/ }
  post "compositions/:template_id", to: "compositions#create", as: :template_compositions,
       format: false, constraints: { template_id: /[^\/]+/ }
  get  "compositions",              to: "compositions#index"
  get  "compositions/:id",          to: "compositions#show", as: :composition
  # カルテ記録の修正（新しい版。skoba/anlage#138）
  get   "compositions/:id/edit",    to: "compositions#edit", as: :edit_composition
  patch "compositions/:id",         to: "compositions#update"
  # カルテ記録の削除（論理削除。skoba/anlage#140）
  delete "compositions/:id",        to: "compositions#destroy"

  get "fhir/r5/StructureDefinition/:id", to: "fhir/profiles#show",
      constraints: { id: /[^\/]+/ }, format: false

  root "templates#index"
end
