require "rails_helper"

# skoba/anlage#98（M3 の W3・W4、docs/design/m3-plan.md）: テンプレートの詳細画面と、版の履歴（系譜）。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し。
RSpec.describe "テンプレートの詳細と版の履歴", type: :request do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  def upload(xml)
    file = Tempfile.new([ "template", ".opt" ])
    file.write(xml)
    file.flush
    Rack::Test::UploadedFile.new(file.path, "text/xml", false, original_filename: "template.opt")
  end

  # 実物の OPT と、そこからラベルを 1 つ置き換えた「同じ template_id で中身が違う」版（実物からの導出）を、
  # 取り込みの経路（POST /templates）で順に登録する。1.0.0 は置き換え済み、1.0.1 が有効になる。
  def register_two_versions
    post templates_path(format: :json), params: { file: upload(opt_path.read) }
    post templates_path(format: :json), params: { file: upload(opt_path.read.sub("Systolic", "Systolic Pressure")) }
    expect(Template.order(:version).pluck(:version, :status)).to eq([ %w[1.0.0 superseded], %w[1.0.1 active] ])
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def detail_rows
    document.css("#template_detail dt").map { _1.text.strip }.zip(document.css("#template_detail dd").map { _1.text.squish }).to_h
  end

  describe "一覧" do
    it "カードから詳細に行ける" do
      Template.build_from_opt_xml(opt_path.read).save!

      get templates_path

      expect(document.css(".template-card a").map { [ _1.text, _1["href"] ] })
        .to include([ "詳細", "/templates/patient_blood_pressure.v1" ])
    end
  end

  describe "GET /templates/:template_id（有効な版の詳細）" do
    before { register_two_versions }

    it "見出しと、template_id・登録版・帳票の可否・項目数・パスカードの枚数が出る" do
      get "/templates/patient_blood_pressure.v1"

      expect(response).to have_http_status(:ok)
      template = Template.active.find_by!(template_id: "patient_blood_pressure.v1")
      expect(document.css("main#workspace > h1").text).to eq("テンプレート: #{template.web_template['concept']}")
      expect(detail_rows).to include(
        "template_id" => "patient_blood_pressure.v1",
        "版" => "登録版 v1.0.1",
        "帳票" => "保存できます",
        "項目数" => template.fields.size.to_s,
        "パスカード" => "#{template.pathcards.size} 枚"
      )
    end

    it "詳細から帳票に入力できる" do
      get "/templates/patient_blood_pressure.v1"

      expect(document.css("#template_actions a").map { [ _1.text, _1["href"] ] })
        .to include([ "帳票に入力", "/forms/patient_blood_pressure.v1" ])
    end

    it "版の履歴に、同じ template_id の版が新しい順に並び、有効な版に印が付く" do
      get "/templates/patient_blood_pressure.v1"

      expect(document.css("#template_versions > h2").text).to eq("版の履歴")
      expect(document.css("#template_versions li").map { _1.text.squish }).to eq([
        "登録版 v1.0.1 有効（この版） 前の版との差分", "登録版 v1.0.0 置き換え済み"
      ])
      expect(document.css("#template_versions li a").map { _1["href"] }).to eq([
        "/templates/patient_blood_pressure.v1/diff?from=1.0.0&to=1.0.1", "/templates/patient_blood_pressure.v1/versions/1.0.0"
      ])
    end

    # skoba/anlage#102（M3 の W6）: そのテンプレートのすべての FHIR プロファイルへのリンク（OPT のエントリ順）
    it "FHIR プロファイルの欄に、すべてのプロファイルへのリンクが出る" do
      get "/templates/patient_blood_pressure.v1"

      expect(document.css("#template_fhir_profiles > h2").text).to eq("FHIR プロファイル")
      expect(document.css("#template_fhir_profiles li a").map { [ _1.text, _1["href"] ] }).to eq([
        [ "openehr-observation-heart-rate-pulse-v1", "/fhir/r5/StructureDefinition/openehr-observation-heart-rate-pulse-v1" ],
        [ "openehr-observation-blood-pressure-v1", "/fhir/r5/StructureDefinition/openehr-observation-blood-pressure-v1" ]
      ])
    end

    it "登録されていない template_id は 404" do
      get "/templates/no_such_template"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /templates/:template_id/versions/:version（置き換えられた版の詳細）" do
    before { register_two_versions }

    it "その版の中身が出て、置き換え済みであることと、有効な版へのリンクが出る。帳票への入力は出ない" do
      get "/templates/patient_blood_pressure.v1/versions/1.0.0"

      expect(response).to have_http_status(:ok)
      expect(detail_rows).to include("版" => "登録版 v1.0.0")
      expect(document.css("#template_superseded").text.squish).to eq("この版は置き換えられています。 有効な版を見る")
      expect(document.css("#template_superseded a").map { _1["href"] }).to eq([ "/templates/patient_blood_pressure.v1" ])
      expect(document.css("#template_actions a").map(&:text)).not_to include("帳票に入力")
    end

    it "無い版は 404" do
      get "/templates/patient_blood_pressure.v1/versions/9.9.9"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "閲覧専用のテンプレート（jp_referral）" do
    it "帳票の行に、閲覧専用であることと理由が出る" do
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).save!

      get "/templates/jp_referral"

      expect(detail_rows["帳票"]).to start_with("閲覧専用（").and include("INSTRUCTION")
      expect(detail_rows["版"]).to eq("登録版 v1.0.0／テンプレート版 0.2.0")
    end
  end
end
