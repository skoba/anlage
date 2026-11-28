require "rails_helper"

# Postman の「患者 ID から EHR を引く」が使う入口（openehr-rails 0.13.0 から。#95）を、初期データで確かめる。
# スクリプトは応答の ehr_id/value を読む（spec/integration/postman_collection_spec.rb）
RSpec.describe "患者 ID から EHR を引く（GET /openehr/v1/ehr）", type: :request do
  before { Evaluation::Datasets.build("demo_initial") }

  it "患者 ID と anlage の名前空間で、その患者の EHR が返り、ehr_id/value が EHR ID" do
    get "/openehr/v1/ehr", params: { subject_id: "DEMO-01", subject_namespace: PatientsController::SUBJECT_NAMESPACE }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("ehr_id", "value")).to eq(OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01").ehr_id)
  end

  it "無い患者 ID は 404" do
    get "/openehr/v1/ehr", params: { subject_id: "DEMO-99", subject_namespace: PatientsController::SUBJECT_NAMESPACE }

    expect(response).to have_http_status(:not_found)
  end
end
