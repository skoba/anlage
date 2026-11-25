require "rails_helper"

# skoba/anlage#130（M3 の P1、docs/design/m3-plan.md 7 節）: 患者（EHR）の一覧と作成。
# 患者 = EHR 1 つ（OpenehrRails::Rm::Ehr）。画面で持つのは患者 ID（subject_id）と名前空間（subject_namespace、既定 anlage）だけ。
# 文言は docs/demo/ui-vocabulary.md の「患者」の行
RSpec.describe "患者（EHR）の一覧と作成（#130）", type: :request do
  def document = Nokogiri::HTML(response.body)

  it "患者がいなければ、空状態と作成の欄を出す" do
    get "/patients"

    expect(response).to have_http_status(:ok)
    expect(document.at_css("h1").text).to eq("患者")
    expect(response.body).to include("患者はまだいません。")
    expect(document.at_css("label[for='patient_subject_id']").text).to eq("患者 ID")
    expect(document.at_css("form button").text).to eq("患者を作る")
  end

  it "患者 ID を入れて作ると、EHR が 1 つでき、患者の画面に移り、一覧に出る" do
    expect { post "/patients", params: { patient: { subject_id: "P-0001" } } }
      .to change(OpenehrRails::Rm::Ehr, :count).by(1)

    ehr = OpenehrRails::Rm::Ehr.last
    expect(ehr).to have_attributes(subject_id: "P-0001", subject_namespace: "anlage")
    expect(ehr.ehr_id).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(response).to redirect_to("/patients/#{ehr.ehr_id}")

    follow_redirect!
    expect(document.at_css("h1").text).to eq("患者: P-0001")
    expect(response.body).to include(ehr.ehr_id)

    get "/patients"
    expect(document.css("table.patients tbody tr").map { |row| row.css("td").map { _1.text.strip } })
      .to eq([ [ "P-0001", "anlage", ehr.ehr_id ] ])
    expect(document.at_css("table.patients a")["href"]).to eq("/patients/#{ehr.ehr_id}")
  end

  it "同じ患者 ID（同じ名前空間）は 2 つ作れない（422）" do
    post "/patients", params: { patient: { subject_id: "P-0001" } }

    expect { post "/patients", params: { patient: { subject_id: "P-0001" } } }.not_to change(OpenehrRails::Rm::Ehr, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("この患者 ID はすでにあります")
  end

  it "患者 ID が空なら 422" do
    expect { post "/patients", params: { patient: { subject_id: " " } } }.not_to change(OpenehrRails::Rm::Ehr, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("患者 ID を入力してください")
  end

  it "無い患者の画面は 404" do
    get "/patients/00000000-0000-0000-0000-000000000000"

    expect(response).to have_http_status(:not_found)
  end
end
