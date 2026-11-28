require "rails_helper"

# 定義の組の画面（読むだけ）。docs/design/definition-registration-plan.md 4 節、skoba/anlage#296、R-20261128-7。
# 書き込み（登録・動かす・戻す）は rake だけ。組は spec/fixtures/definitions/clinic と、それを 0.2.0 にした写し（血圧の部品を外した）。
# clinic の logic/bmi_rules.yml には reviewed_by が無いので、検査は「案」（D8）を 1 件出す
RSpec.describe "定義の組の画面（/definitions）", type: :request do
  let(:fixture) { Rails.root.join("spec/fixtures/definitions/clinic") }
  let(:ehr) { OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01") }
  let(:first) { DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake（spec）").bundle.tap(&:activate!) }
  let(:second) do
    dir = Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(fixture, _1) }
    chart = dir.join("screens/patient_chart.yml")
    chart.write(chart.read.sub(/  - id: blood_pressure\n.*?(?=  - id: actions)/m, ""))
    dir.join("bundle.yml").write(dir.join("bundle.yml").read.sub(/^version: .*$/, "version: 0.2.0"))
    DefinitionBundle.register(Definitions::Files.read(dir), registered_by: "rake（spec）").bundle
  ensure
    FileUtils.remove_entry(dir.dirname) if dir
  end

  # 組の検査は、登録済みのテンプレートで行うので、初期データを先に入れる
  before do
    Evaluation::Datasets.build("demo_initial")
    first
    second
  end

  def document = Nokogiri::HTML(response.body)
  def rows = document.css("#definition_bundles tbody tr").map { |tr| tr.css("td").map { _1.text.squish } }
  def diff_lines(path) = document.css("[data-definition-diff='#{path}'] .diff-line").map(&:text)

  it "一覧: 組と版、状態、登録した人、いまのテンプレートでの検査の結果。読むだけであることと、rake の道を書く" do
    get definitions_path

    expect(response).to have_http_status(:ok)
    expect(rows.map { _1.first(5) }).to eq([
      [ "clinic_spec", "0.2.0", "下書き", "rake（spec）", "通る（案 1 件）" ],
      [ "clinic_spec", "0.1.0", "動いている", "rake（spec）", "通る（案 1 件）" ]
    ])
    expect(document.at_css("#definition_bundles tbody tr a")["href"]).to eq(definition_path(second))
    expect(document.at_css("#definitions_note").text.squish)
      .to eq("この画面は読むだけです。登録・動かす・戻すは、サーバで rake definitions:register・definitions:activate・definitions:restore を実行します。")
  end

  it "版の画面: 検査の結果、遷移の図、前の版との差分（変えたファイルだけ）" do
    get definition_path(second)

    expect(document.at_css("h1").text).to eq("定義の組 clinic_spec 0.2.0")
    expect(document.at_css("#definition_lint").text.squish).to include("通る（案 1 件）")
    expect(document.at_css("#definition_diagram svg.transition-diagram")).to be_present
    expect(document.at_css("#definition_diff h2").text).to eq("前の版（0.1.0）との差分")
    expect(diff_lines("bundle.yml")).to include("-version: 0.1.0", "+version: 0.2.0")
    expect(diff_lines("screens/patient_chart.yml")).to include("-  - id: blood_pressure")
    expect(diff_lines("screens/patient_chart.yml")).not_to include(a_string_starting_with("+"))
    expect(document.css("[data-definition-diff]").map { _1["data-definition-diff"] }).to eq(%w[bundle.yml screens/patient_chart.yml])
  end

  it "前の版の無い版は、差分の代わりに、その旨を出す" do
    get definition_path(first)

    expect(document.at_css("#definition_diff").text.squish).to include("前の版はありません。")
  end

  describe "試しに表示のリンク" do
    it "下書きで、患者を選んでいれば、その患者の画面に ?preview= を付けたリンク" do
      post select_patient_path(ehr.ehr_id)
      get definition_path(second)

      expect(document.at_css("a#definition_preview")["href"]).to eq(patient_path(ehr.ehr_id, preview: second.id))
      expect(document.at_css("a#definition_preview").text).to eq("この版を、患者 DEMO-01 の画面で試しに表示")
    end

    it "患者を選んでいなければ、選ぶように書く。下書きでなければ出さない" do
      get definition_path(second)
      expect(document.at_css("a#definition_preview")).to be_nil
      expect(document.at_css("#definition_preview_note").text.squish).to eq("試しに表示するには、先に患者を選んでください。")

      post select_patient_path(ehr.ehr_id)
      get definition_path(first)
      expect(document.at_css("a#definition_preview")).to be_nil
      expect(document.at_css("#definition_preview_note")).to be_nil
    end
  end

  it "いまのテンプレートで検査に通らない版は、エラーの一覧を出し、図は出さない" do
    Template.active.find_by!(template_id: "LabResultReport").supersede!

    get definition_path(first)

    expect(response).to have_http_status(:ok)
    expect(document.at_css("#definition_lint").text.squish).to include("通らない（エラー")
    expect(document.css("#definition_lint li").map(&:text)).to include(a_string_including("LabResultReport"))
    expect(document.at_css("#definition_diagram").text.squish).to eq("遷移の図 検査でエラーがあるので、図は出しません。")
  end

  it "無い行は 404" do
    get definition_path(0)

    expect(response).to have_http_status(:not_found)
  end

  it "画面から登録・動かす・戻す道が無い（/definitions の route は GET だけ）" do
    routes = Rails.application.routes.routes.select { _1.path.spec.to_s.start_with?("/definitions") }

    expect(routes.map(&:verb).uniq).to eq([ "GET" ])
    expect(routes.size).to eq(2)
  end
end
