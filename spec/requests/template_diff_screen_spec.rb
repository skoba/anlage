require "rails_helper"

# skoba/anlage#100（M3 の W5、docs/design/m3-plan.md）: 登録済みの 2 つの版の差分の画面。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し。
RSpec.describe "テンプレートの版差分", type: :request do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  def upload(xml)
    file = Tempfile.new([ "template", ".opt" ])
    file.write(xml)
    file.flush
    Rack::Test::UploadedFile.new(file.path, "text/xml", false, original_filename: "template.opt")
  end

  # 実物の OPT と、ラベルを 1 つ置き換えた版（実物からの導出）を、取り込みの経路で順に登録する
  before do
    post templates_path(format: :json), params: { file: upload(opt_path.read) }
    post templates_path(format: :json), params: { file: upload(opt_path.read.sub("Systolic", "Systolic Pressure")) }
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "版の履歴から、前の版との差分に行ける" do
    get "/templates/patient_blood_pressure.v1"

    expect(document.css("#template_versions li a").map { [ _1.text, _1["href"] ] })
      .to include([ "前の版との差分", "/templates/patient_blood_pressure.v1/diff?from=1.0.0&to=1.0.1" ])
  end

  it "2 つの版を指定すると、変更された項目と、パスカードの差分（ラベルの前後）が出る" do
    get "/templates/patient_blood_pressure.v1/diff", params: { from: "1.0.0", to: "1.0.1" }

    expect(response).to have_http_status(:ok)
    expect(document.css("main#workspace > h1").text.squish).to eq("版の差分: patient_blood_pressure.v1（登録版 v1.0.0 → 登録版 v1.0.1）")
    expect(document.css("#field_diff > h2").text).to eq("項目の差分")
    expect(document.css("#field_diff .diff-changed").size).to eq(1)
    expect(document.css("#pathcard_diff > h2").text).to eq("パスカードの差分")
    changed = document.css("#pathcard_diff .diff-changed")
    expect(changed.size).to eq(1)
    expect(changed.first.text.squish).to include("ラベル").and include("Systolic").and include("Systolic Pressure")
  end

  it "同じ版どうしなら、差分が無い旨が出る" do
    get "/templates/patient_blood_pressure.v1/diff", params: { from: "1.0.1", to: "1.0.1" }

    expect(response).to have_http_status(:ok)
    expect(document.css("#field_diff p").text).to eq("項目の差分はありません。")
    expect(document.css("#pathcard_diff p").text).to eq("パスカードの差分はありません。")
  end

  it "無い版を指定したら 404" do
    get "/templates/patient_blood_pressure.v1/diff", params: { from: "1.0.0", to: "9.9.9" }

    expect(response).to have_http_status(:not_found)
  end
end
