require "rails_helper"

# 定義の組（ディレクトリ）の検査（docs/design/definition-layer-plan.md 2.2・5 節の D-1、skoba/anlage#257）。
# 知識源は登録済みのテンプレートだけ（実物の OPT: spec/fixtures/opt）。組は spec/fixtures/definitions/clinic を写して一部を書き換える
RSpec.describe Definitions::Linter do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  let(:dir) { Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(Rails.root.join("spec/fixtures/definitions/clinic"), _1) } }

  after { FileUtils.remove_entry(dir.dirname) }

  def edit(relative)
    path = dir.join(relative)
    data = YAML.safe_load(path.read)
    yield data
    path.write(data.to_yaml)
  end

  def problems = described_class.call(dir).problems
  def codes = problems.map(&:code)

  it "書式どおりで参照がそろった組は、エラーなし（reviewed_by の無いロジックは D8 の案だけ）" do
    expect(problems.map { [ _1.code, _1.severity ] }).to eq([ [ "D8", :draft ] ])
    expect(described_class.call(dir)).to be_ok
  end

  it "D1: 書式の誤りは、ファイルと位置つき" do
    edit("screens/lab_entry.yml") { _1["sections"][0]["form"] = "x" }

    expect(problems.find { _1.code == "D1" }.to_h).to include(definition: "screens/lab_entry.yml", pointer: "/sections/0/form")
  end

  it "D2: id の重なり（2 つの画面の section が同じ id）" do
    edit("screens/lab_entry.yml") { _1["sections"][0]["id"] = "labs" }

    problem = problems.find { _1.code == "D2" }
    expect(problem.to_h).to include(definition: "screens/lab_entry.yml", pointer: "/sections/0/id", id: "labs")
    expect(problem.message).to include("screens/patient_chart.yml")
  end

  it "D3: 存在しない field を参照する画面の定義はエラーになり、候補を出す" do
    edit("screens/patient_chart.yml") { _1["sections"][1]["from"]["field"] = "laboratory_test_analyte_at0002" }

    problem = problems.find { _1.code == "D3" }
    expect(problem.pointer).to eq("/sections/1/from/field")
    expect(problem.id).to eq("labs")
    expect(problem.message).to eq("\"laboratory_test_analyte_at0002\" は LabResultReport に無い")
    expect(problem.candidates).to eq([ "laboratory_test_result_at0005（検査名）", "laboratory_test_analyte_at0024（分析名）", "laboratory_test_analyte_at0001（分析結果）" ])
  end

  it "D3: 登録されていないテンプレート、アーキタイプに無い at-code" do
    edit("screens/lab_entry.yml") { _1["sections"][0]["from"]["template"] = "LabResult" }
    edit("screens/patient_chart.yml") { _1["sections"][0]["columns"] = %w[at0002 at9999] }

    expect(problems.select { _1.code == "D3" }.map { [ _1.pointer, _1.message ] }).to contain_exactly(
      [ "/sections/0/from/template", "テンプレート LabResult は登録されていない" ],
      [ "/sections/0/columns/1", "at-code at9999 は openEHR-EHR-EVALUATION.problem_diagnosis.v1 の項目に無い" ]
    )
  end

  it "D4: 部品と項目の型が合わない（time_series に DV_TEXT、problem_list に problem_diagnosis 以外）" do
    edit("screens/patient_chart.yml") do |screen|
      screen["sections"][2]["from"] = { "template" => "LabResultReport", "field" => "laboratory_test_analyte_at0024" }
      screen["sections"][0]["from"] = { "archetype" => "openEHR-EHR-OBSERVATION.blood_pressure.v2" }
      screen["sections"][0].delete("columns")
    end

    expect(problems.select { _1.code == "D4" }.map(&:message)).to contain_exactly(
      "time_series の項目 laboratory_test_analyte_at0024 は DV_TEXT。DV_QUANTITY か DV_COUNT でなければならない",
      "problem_list は openEHR-EHR-EVALUATION.problem_diagnosis.v1 だけを受ける"
    )
  end

  it "D5: 遷移先の画面・帳票が無い" do
    edit("screens/patient_chart.yml") { _1["sections"][3]["items"][0]["open"] = { "screen" => "lab_view" } }
    edit("screens/lab_entry.yml") { _1["sections"][1]["items"][0]["open"]["form"] = "LabResult" }

    expect(problems.select { _1.code == "D5" }.map(&:message)).to contain_exactly(
      "画面 lab_view は組に無い", "帳票 LabResult は登録されていない"
    )
  end

  it "D6: どこからもたどり着けない画面" do
    edit("screens/patient_chart.yml") { _1["sections"].delete_at(3) }

    problem = problems.find { _1.code == "D6" }
    expect(problem.to_h).to include(definition: "screens/lab_entry.yml", message: "画面 lab_entry には、start からもボタンからもたどり着けない")
  end

  it "D7: ロジックの入力が帳票に無い、式の誤り、入力に無い識別子" do
    edit("logic/bmi_rules.yml") do |logic|
      logic["rules"][0]["inputs"] = %w[height weight]
      logic["rules"][0]["formula"] = "body_weight / (height / 100) ^"
      logic["rules"][1]["cases"][0]["when"] = "bmi < 18.5"
    end

    d7 = problems.select { _1.code == "D7" }
    expect(d7.map(&:pointer)).to contain_exactly("/rules/0/inputs/1", "/rules/0/formula", "/rules/1/cases/0/when")
    expect(d7.find { _1.pointer == "/rules/0/inputs/1" }.message).to eq("入力 weight は bmi_calculation の帳票に無い")
    expect(d7.find { _1.pointer == "/rules/0/inputs/1" }.candidates).to include("body_weight（体重）")
    expect(d7.find { _1.pointer == "/rules/0/formula" }.message).to start_with("式を読めない（") # 理由は Opt::Formula の文
    expect(d7.find { _1.pointer == "/rules/1/cases/0/when" }.message).to eq("式に、入力に無い識別子 bmi がある")
  end

  it "D8: 出どころもレビュー者も無いロジックは案（エラーではない）" do
    problem = problems.find { _1.code == "D8" }

    expect(problem.to_h).to include(definition: "logic/bmi_rules.yml", severity: "draft")
    expect(problem.message).to eq("reviewed_by が無い。案として扱い、保存には効かない")
  end

  it "目録にある定義のファイルが無い（D3）" do
    dir.join("logic/bmi_rules.yml").delete

    expect(problems.map { [ _1.code, _1.definition, _1.message ] }).to include([ "D3", "bundle.yml", "定義のファイル logic/bmi_rules.yml が無い" ])
  end
end
