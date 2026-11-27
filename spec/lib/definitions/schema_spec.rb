require "rails_helper"

# D1: 書式（スキーマ）に合う（docs/design/definition-layer-plan.md 2.2、書式は docs/reports/definitions-log.md R1、skoba/anlage#257）。
# 未知のキー、必須のキーが無い、型が違う、を JSON Pointer の位置つきで返す
RSpec.describe Definitions::Schema do
  def check(kind, data) = described_class.check(kind, data, definition: "#{kind}s/x.yml")

  let(:screen) do
    { "screen" => "x", "version" => "1.0.0",
      "sections" => [ { "id" => "labs", "component" => "lab_table", "from" => { "template" => "LabResultReport" } },
                      { "id" => "actions", "component" => "buttons",
                        "items" => [ { "id" => "enter", "label" => "入力", "open" => { "form" => "LabResultReport", "then" => { "screen" => "x" } } } ] } ] }
  end

  it "書式どおりの画面の定義は問題なし" do
    expect(check("screen", screen)).to be_empty
  end

  it "必須のキーが無い" do
    problems = check("screen", screen.except("version"))

    expect(problems.map { [ _1.code, _1.pointer, _1.message ] }).to eq([ [ "D1", "", "必須のキー version が無い" ] ])
  end

  it "未知のキーは、位置と、使えるキーを候補に出す" do
    screen["sections"][0]["form"] = "x"
    problem = check("screen", screen).sole

    expect(problem.pointer).to eq("/sections/0/form")
    expect(problem.message).to eq("未知のキー form")
    expect(problem.candidates).to include("from", "columns")
    expect(problem.id).to eq("labs")
  end

  it "型が違う（配列のところに文字列）" do
    screen["sections"] = "labs"

    expect(check("screen", screen).sole.message).to eq("sections は配列でなければならない")
  end

  it "列挙に無い値（部品の名前）" do
    screen["sections"][0]["component"] = "chart"
    problem = check("screen", screen).sole

    expect(problem.pointer).to eq("/sections/0/component")
    expect(problem.candidates).to include("time_series", "lab_table")
  end

  it "ボタンの open は form か screen のどちらか 1 つ" do
    screen["sections"][1]["items"][0]["open"] = { "then" => { "screen" => "x" } }

    expect(check("screen", screen).sole.message).to eq("open には form か screen のどちらか 1 つが要る")
  end

  it "ロジック: rule は formula か cases のどちらか 1 つ。round は整数" do
    logic = { "logic" => "bmi_rules", "version" => "1.0.0", "template" => "bmi_calculation",
              "rules" => [ { "id" => "bmi", "target" => "body_mass_index", "inputs" => %w[height body_weight], "round" => "1" } ] }

    expect(check("logic", logic).map(&:message)).to contain_exactly("rule には formula か cases のどちらか 1 つが要る", "round は整数でなければならない")
  end

  it "組の目録: screens があれば start が要る" do
    bundle = { "bundle" => "b", "version" => "0.1.0", "title" => "t", "screens" => [ "x" ] }

    expect(check("bundle", bundle).sole.message).to eq("screens があるときは start が要る")
  end
end
