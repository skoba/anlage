require "rails_helper"

# skoba/anlage#138（M3 の P4、docs/design/m3-plan.md 7.3）: 修正できる記録の判定。
# 記録を読み戻して（Opt::CompositionReader）組み直し（Opt::CompositionBuilder）、content が保存したものと同じときだけ修正できる。
# 読み戻せない形（Issue #30 の残り: INSTRUCTION、多段の CLUSTER など）を含む記録は、修正すると値を黙って落とすので、修正を出さない
RSpec.describe Opt::CompositionEditability do
  def template_for(fixture) = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture}").read)

  def canonical(template, values)
    JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(Opt::CompositionBuilder.new(template, values).build).serialize)
  end

  it "ProblemList の記録は修正できる" do
    template = template_for("ProblemList.opt")

    expect(described_class.editable?(template, canonical(template, "problem_diagnosis_at0002" => "高血圧症"))).to be(true)
  end

  it "数量（単位つき）の記録は修正できる（単位も読み戻す）" do
    template = template_for("patient_blood_pressure.opt")
    values = { "blood_pressure_systolic" => "120", "blood_pressure_systolic__units" => "mm[Hg]" }

    expect(described_class.editable?(template, canonical(template, values))).to be(true)
  end

  it "読み戻せない形（INSTRUCTION の値）を含む jp_referral の記録は修正できない" do
    template = template_for("jp_referral.opt")
    values = { "service_request_at0121" => "精査依頼", "problem_diagnosis_at0002" => "2型糖尿病" }

    expect(described_class.editable?(template, canonical(template, values))).to be(false)
  end
end
