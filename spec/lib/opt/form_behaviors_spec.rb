require "rails_helper"

# skoba/anlage#47 変更 4: config/form_behaviors.yml（GDL2 の rule/when と同型）をサーバで適用する。
# サーバが権威: editable: false の target は inputs が揃えば常に再計算値で上書き、editable: true は
# 空欄のときだけ提案で埋め、人間が書き換えた印（<target>__edited）があれば埋めない（裁定 C）。
# 判定の区分は日本肥満学会の肥満度分類（裁定 B）。
RSpec.describe Opt::FormBehaviors do
  let(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read).tap(&:save!).reload
  end

  def apply(values) = described_class.apply(template, values)

  it "身長 170 cm・体重 65 kg → BMI 22.5（小数 1 桁）・判定「普通体重」" do
    result = apply("height" => "170", "body_weight" => "65", "body_mass_index" => "", "body_mass_index_at0013" => "")

    expect(result).to include("body_mass_index" => "22.5", "body_mass_index_at0013" => "普通体重")
  end

  it "BMI（editable: false）はクライアントが送った値を再計算値で上書きする" do
    result = apply("height" => "170", "body_weight" => "65", "body_mass_index" => "99", "body_mass_index_at0013" => "")

    expect(result["body_mass_index"]).to eq("22.5")
  end

  it "判定（editable: true）は記入済みなら尊重し、空欄のときだけ埋める" do
    result = apply("height" => "170", "body_weight" => "65", "body_mass_index_at0013" => "肥満（1度）")

    expect(result["body_mass_index_at0013"]).to eq("肥満（1度）")
  end

  it "判定を人間が消した印（__edited）があれば空欄のまま保存する。印は values から取り除く" do
    result = apply("height" => "170", "body_weight" => "65", "body_mass_index_at0013" => "", "body_mass_index_at0013__edited" => "1")

    expect(result["body_mass_index_at0013"]).to eq("")
    expect(result).not_to have_key("body_mass_index_at0013__edited")
  end

  it "inputs が揃わなければ計算しない（BMI も判定も送られたまま）" do
    result = apply("height" => "", "body_weight" => "65", "body_mass_index" => "", "body_mass_index_at0013" => "")

    expect(result).to include("body_mass_index" => "", "body_mass_index_at0013" => "")
  end

  # 身長 100 cm なら BMI＝体重。区分の境界は「未満」で切る（18.5 は普通体重、25 は肥満（1度））
  {
    "18.4" => "低体重", "18.5" => "普通体重", "24.9" => "普通体重", "25" => "肥満（1度）",
    "30" => "肥満（2度）", "35" => "肥満（3度）", "39.9" => "肥満（3度）", "40" => "肥満（4度）"
  }.each do |bmi, category|
    it "BMI #{bmi} → #{category}（日本肥満学会の 6 区分）" do
      expect(apply("height" => "100", "body_weight" => bmi)["body_mass_index_at0013"]).to eq(category)
    end
  end

  it "振る舞いを宣言していないテンプレートの values はそのまま" do
    problem_list = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!)
    values = { "problem_diagnosis_at0002" => "高血圧症" }

    expect(described_class.apply(problem_list, values)).to eq(values)
  end

  it ".rules_for はクライアントへ渡す宣言（yml の写し）を返す" do
    rules = described_class.rules_for("bmi_calculation")

    expect(rules.map { _1["target"] }).to eq(%w[body_mass_index body_mass_index_at0013])
    expect(rules.first).to include("inputs" => %w[height body_weight], "formula" => "body_weight / (height / 100) ^ 2", "round" => 1, "editable" => false)
    expect(described_class.rules_for("ProblemList")).to eq([])
  end
end
