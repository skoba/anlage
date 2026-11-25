require "rails_helper"

# skoba/anlage#134（M3 の P2、docs/design/m3-plan.md 7 節）: いまの患者を選ぶ。選んだ患者はセッションに持ち（session[:ehr_id]）、
# 共通ナビの下に出す。ナビのリンク（6 つ）は変えない。文言は docs/demo/ui-vocabulary.md の「患者」の行
RSpec.describe "いまの患者を選ぶ（#134）", type: :request do
  def document = Nokogiri::HTML(response.body)

  def current_patient_text = document.at_css("#current_patient")&.text.to_s.squish

  let!(:patient) { OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-0001", subject_namespace: "anlage") }

  it "選んでいなければ、ナビの下に「患者を選んでいません」と出る" do
    get "/templates"

    expect(current_patient_text).to eq("いまの患者: 患者を選んでいません")
  end

  it "患者の画面で選ぶと、どの画面のナビの下にも、いまの患者が出る（AQL 照会の画面も）" do
    get "/patients/#{patient.ehr_id}"
    expect(document.at_css("form[action='/patients/#{patient.ehr_id}/select'] button").text).to eq("この患者を選ぶ")

    post "/patients/#{patient.ehr_id}/select"
    expect(response).to redirect_to("/patients/#{patient.ehr_id}")

    [ "/templates", "/compositions", "/openehr/query" ].each do |path|
      get path
      expect(current_patient_text).to eq("いまの患者: P-0001 選択を外す"), "#{path} のいまの患者"
    end
  end

  it "選択を外せる" do
    post "/patients/#{patient.ehr_id}/select"

    delete "/patients/selection"
    expect(response).to redirect_to("/patients")

    get "/templates"
    expect(current_patient_text).to eq("いまの患者: 患者を選んでいません")
  end

  it "無い EHR は選べない（404）" do
    post "/patients/00000000-0000-0000-0000-000000000000/select"

    expect(response).to have_http_status(:not_found)
  end

  it "選んだ患者の EHR が無くなっていれば、選んでいないものとして扱う" do
    post "/patients/#{patient.ehr_id}/select"
    patient.destroy!

    get "/templates"
    expect(current_patient_text).to eq("いまの患者: 患者を選んでいません")
  end
end
