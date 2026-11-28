require "rails_helper"

# AI に渡す材料（docs/design/definition-layer-plan.md 2.4、R-20261127-21 の回答 3、skoba/anlage#259）。
# 外の LLM に送られる前提で作る（コンテンツ防火壁）。入れるのは、テンプレートの項目の名前・見出し・型・単位、部品の一覧、スキーマ、例。
# 入れないのは、記録の中身、患者や EHR の ID、パスカードの bindings と用語のコード、用語マスターの文言、外部の値集合の中身、OPT のファイルそのもの
RSpec.describe Definitions::Context do
  before { Evaluation::Datasets.build("demo_initial") } # 初期データ（記録と患者がある状態）

  let(:context) { described_class.call }
  let(:json) { JSON.generate(context) }

  it "テンプレートの項目は、名前・見出し・型・単位・アーキタイプ・at-code だけ" do
    lab = context[:templates].find { _1[:template_id] == "LabResultReport" }

    expect(lab[:fields]).to include({ name: "laboratory_test_analyte_at0024", label: "分析名", rm_type: "DV_TEXT",
                                      archetype_id: "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1", node_id: "at0024" })
    expect(context[:templates].flat_map { _1[:fields] }.flat_map(&:keys).uniq).to all(be_in(%i[name label rm_type archetype_id node_id units]))
  end

  it "部品の一覧と、受け取るもの" do
    expect(context[:components].map { _1[:name] }).to eq(Definitions::Schema::COMPONENTS)
    expect(context[:components].find { _1[:name] == "time_series" }[:accepts]).to include("DV_QUANTITY")
  end

  # R-20261128-7 の回答 4: AI に、from の書き忘れが黙って「全部を出す」にならないことを伝える
  it "from の決まり（記録を引く部品は from が要る、全体から引くなら from: { auto: true }）" do
    expect(context[:from_rule]).to include("from が要る", "from: { auto: true }")
    expect(context[:components].find { _1[:name] == "lab_table" }[:accepts]).to include("from: { auto: true }")
    expect(context[:schemas]["screen"].dig("properties", "sections", "items", "properties", "from", "properties", "auto")).to eq("enum" => [ true ])
  end

  it "スキーマは検査器から書き出した JSON Schema（正は検査器）" do
    screen = context[:schemas]["screen"]

    expect(screen).to include("type" => "object", "required" => %w[screen version sections], "additionalProperties" => false)
    expect(screen.dig("properties", "sections", "items", "properties", "component", "enum")).to eq(Definitions::Schema::COMPONENTS)
  end

  it "例の組（docs/definitions/example）は、検査を通る（エラー 0）" do
    expect(context[:examples].keys).to include("bundle.yml", "screens/patient_chart.yml")
    expect(Definitions::Linter.call(Rails.root.join("docs/definitions/example"))).to be_ok
  end

  it "材料に、bindings・用語のコード・値集合・記録の値・患者と EHR の ID・OPT が出ない" do
    ehr = OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01")
    record = OpenehrRails::Rm::Composition.latest.where(ehr:).first

    expect(json).not_to include("code_bindings", "bindings", "code_list", "code_labels", "value_set_uri", "terminology_id")
    expect(json).not_to include("5A11", "at0074") # 初期データの ICD-11 コード、診断確度の値集合のコード
    expect(json).not_to include("2型糖尿病", "DEMO-01", ehr.ehr_id, record.uid)
    expect(json).not_to include("<template", "<?xml")
  end
end
