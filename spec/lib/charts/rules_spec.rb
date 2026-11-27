require "rails_helper"

# 患者の画面（U1）の部品を決める規則（skoba/anlage#219、docs/design/u1-patient-chart-plan.md 1.2・1.5、R-20261127-13）。
# 部品はテンプレートの entry と field の RM の型とアーキタイプから決める。列の名前・単位・選択肢の表示はテンプレートから
RSpec.describe Charts::Rules do
  def template(name) = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read)
  def components(name) = described_class.for(template(name))

  it "problem_diagnosis の entry はプロブレムリスト。列は診断名・診断確度・発症日で、ラベルはテンプレートから" do
    problem = components("ProblemList").find { _1.kind == :problem_list }

    expect(problem.fields.transform_values { _1["label"] }).to eq("diagnosis" => "プロブレム・診断名", "certainty" => "診断確度", "onset" => "発症日時")
  end

  it "OBSERVATION の数量の field は、field ごとの時系列（単位はテンプレートから）" do
    series = components("CardiologyEncounter").select { _1.kind == :time_series }

    expect(series.map { _1.fields["value"]["label"] }).to eq(%w[収縮期 拡張期])
    expect(series.map { _1.fields["value"]["units"] }).to eq([ "mm[Hg]", "mm[Hg]" ])
  end

  it "検査の分析（laboratory_test_analyte）は検査結果の時系列表。分析名の field と、分析結果の field" do
    lab = components("LabResultReport")

    expect(lab.map(&:kind)).to eq([ :lab_table ])
    expect(lab.first.fields.transform_values { _1["label"] }).to eq("name" => "分析名", "value" => "分析結果")
  end

  it "INSTRUCTION を持つテンプレートは依頼と紹介状。同じテンプレートの problem_diagnosis はプロブレムリストにも入る" do
    kinds = components("jp_referral").map(&:kind)

    expect(kinds).to include(:orders, :problem_list)
    expect(kinds).not_to include(:time_series)
  end

  it "身長・体重・BMI（bmi_calculation）は、数量の field ごとの時系列" do
    labels = components("bmi_calculation").select { _1.kind == :time_series }.map { _1.fields["value"]["label"] }

    expect(labels).to include("身長", "体重", "Body mass index") # ラベルは OPT の表記のまま
  end
end
