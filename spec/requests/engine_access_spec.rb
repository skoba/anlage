require "rails_helper"

# engine（AQL 照会・FHIR・openEHR REST）への入り方（skoba/anlage#174）。
# openehr-rails の engine は、development／test 以外では OpenehrRails.authenticate_with が無いと 403
# （0.10.0 app/controllers/openehr_rails/application_controller.rb:20-26）。
# anlage は、任意の Basic 認証（OptionalBasicAuth、#163）を与えたときだけ、入口で認証済みとして engine を開ける。
# 与えなければ gem の既定のまま。production は、allow_unauthenticated_access = false で装う。
RSpec.describe "engine への入り方（#174）", type: :request do
  around do |example|
    original = [ OpenehrRails.authenticate_with, OpenehrRails.allow_unauthenticated_access ]
    OpenehrRails.allow_unauthenticated_access = false
    example.run
  ensure
    OpenehrRails.authenticate_with, OpenehrRails.allow_unauthenticated_access = original
  end

  it "Basic 認証を与えたときの設定では、production でも AQL 照会と FHIR が開く" do
    OpenehrRails.authenticate_with = OptionalBasicAuth.engine_hook(username: "demo", password: "s3cret")

    get "/openehr/query"
    expect(response).to have_http_status(:ok)
    get "/openehr/fhir/metadata"
    expect(response).to have_http_status(:ok)
  end

  it "与えないときは、gem の既定のまま production では 403" do
    OpenehrRails.authenticate_with = OptionalBasicAuth.engine_hook(username: nil, password: nil)

    get "/openehr/query"
    expect(response).to have_http_status(:forbidden)
  end

  it "テスト環境は環境変数を与えないので、アプリの設定に hook は無い" do
    expect(OptionalBasicAuth.engine_hook(username: ENV["ANLAGE_BASIC_AUTH_USERNAME"], password: ENV["ANLAGE_BASIC_AUTH_PASSWORD"])).to be_nil
  end
end
