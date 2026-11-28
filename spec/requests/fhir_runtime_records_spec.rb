require "rails_helper"

# FHIR の読み出し（R-20261127-30、R-20261128-1）。anlage の記録は、実行時に登録したテンプレートで RM グラフに入る。
# openehr-rails 0.14.1 の FHIR facade は、そのテンプレートを OpenehrRails::Fhir.template_source から引く
# （config/initializers/openehr.rb）。つなぐ前は、Observation の検索が常に 0 件だった（既知の制限 19）。
RSpec.describe "FHIR の読み出し（初期データの記録）", type: :request do
  before { Evaluation::Datasets.build("demo_initial") }

  let(:demo01) { OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01") }

  def fhir(path, **params)
    get "/openehr/fhir/#{path}", params: params
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  it "DEMO-01 の Observation が検索で出る（血圧の収縮期 148 を含む）" do
    bundle = fhir("Observation", subject: "Patient/#{demo01.ehr_id}")

    expect(bundle["total"]).to be > 0
    values = bundle["entry"].flat_map { |entry| [ entry["resource"], *entry["resource"]["component"] ] }
                            .filter_map { _1.dig("valueQuantity", "value") }
    expect(values).to include(148)
  end

  it "Observation を 1 件、id で取れる" do
    id = fhir("Observation", subject: "Patient/#{demo01.ehr_id}")["entry"].first["resource"]["id"]

    resource = fhir("Observation/#{id}")

    expect(resource).to include("resourceType" => "Observation", "id" => id)
  end

  it "DEMO-01 の Condition（プロブレムリスト）が 3 件出て、clinicalStatus を持つ" do
    bundle = fhir("Condition", subject: "Patient/#{demo01.ehr_id}")

    expect(bundle["total"]).to eq(3)
    bundle["entry"].each { |entry| expect(entry["resource"]["clinicalStatus"]).to be_present }
  end

  # template_id が重なると gem は 500（TemplateSourceError）。Template.active は、ふつう template_id ごとに 1 つだが、
  # 表の制約ではない（supersede! を呼ぶ側が守る）。重なっても、あとから登録したもの 1 つだけを渡す
  it "同じ template_id の active が 2 つあっても 500 にならず、件数も重ならない" do
    original = Template.active.find_by!(template_id: "ProblemList")
    original.dup.tap { |copy| copy.assign_attributes(version: "1.0.1", checksum: "#{original.checksum}-copy") }.save!

    bundle = fhir("Condition", subject: "Patient/#{demo01.ehr_id}")

    expect(bundle["total"]).to eq(3)
  end
end
