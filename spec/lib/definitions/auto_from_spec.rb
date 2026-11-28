require "rails_helper"

# from: { auto: true }（docs/design/definition-registration-plan.md 3 節、skoba/anlage#281、R-20261128-7 の回答 4）。
# 「U1 の規則で、登録済みのテンプレート全体から引く」を、書かないことで表さず、はっきり書く。
# 記録を引く部品で from が無いと D1。生成 AI の書き忘れが、黙って「全部を出す」にならない
RSpec.describe "from: { auto: true }" do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  let(:files) { Definitions::Files.read(Rails.root.join("spec/fixtures/definitions/clinic")) }

  def with_sections(*sections)
    screen = YAML.safe_load(files["screens/patient_chart.yml"])
    screen["sections"] = sections + screen["sections"].select { _1["component"] == "buttons" }
    files.merge("screens/patient_chart.yml" => screen.to_yaml)
  end

  def problems(*sections) = Definitions::Linter.check(with_sections(*sections)).problems.reject { _1.code == "D8" }
  # D1 を通らない画面は読まれないので、その画面への遷移も D5 になる（検査器のこれまでの振る舞い）。ここでは D1 だけを見る
  def d1(*sections) = problems(*sections).select { _1.code == "D1" }

  it "記録を引く部品は、from: { auto: true } で、ほかの参照なしに検査を通る" do
    sections = %w[problem_list time_series lab_table records table].each_with_index.map do |component, index|
      { "id" => "s#{index}", "component" => component, "from" => { "auto" => true } }
    end

    expect(problems(*sections)).to be_empty
  end

  it "records は、auto に rm_type を足して絞れる（依頼と紹介状 = INSTRUCTION）" do
    expect(problems({ "id" => "orders", "component" => "records", "from" => { "auto" => true, "rm_type" => "INSTRUCTION" } })).to be_empty
  end

  it "記録を引く部品で from が無いと D1。直し方（from: { auto: true }）を出す" do
    problem = d1({ "id" => "labs", "component" => "lab_table" }).sole

    expect(problem.to_h).to include(code: "D1", definition: "screens/patient_chart.yml", pointer: "/sections/0", id: "labs")
    expect(problem.message).to eq("lab_table には from が要る。登録済みのテンプレート全体から引くなら from: { auto: true } と書く")
  end

  it "auto は、template・archetype・field・fields と一緒に書けない（D1）" do
    problem = d1({ "id" => "labs", "component" => "lab_table", "from" => { "auto" => true, "template" => "LabResultReport" } }).sole

    expect(problem.to_h).to include(code: "D1", pointer: "/sections/0/from")
    expect(problem.message).to eq("from の auto は rm_type のほかのキーと一緒に書けない（template）")
  end

  it "auto は true だけ（false は書かない）" do
    expect(d1({ "id" => "labs", "component" => "lab_table", "from" => { "auto" => false } }).map(&:pointer)).to eq(%w[/sections/0/from/auto])
  end

  it "記録を引かない部品（buttons・form）は、これまでどおり" do
    expect(problems).to be_empty
  end
end
