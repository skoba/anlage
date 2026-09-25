require "rails_helper"

RSpec.describe Opt::CompositionReader do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }
  let(:template) { Template.build_from_opt_xml(opt_xml) }

  def build_composition_json(template, values)
    rm_composition = Opt::CompositionBuilder.new(template, values).build
    OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize
  end

  it "reads field values back out of a composition it round-trips through CompositionBuilder" do
    values = template.fields.index_with { "42" }.transform_keys { |f| f["name"] }
    json = build_composition_json(template, values)

    read_back = described_class.call(template, json)

    expect(read_back["blood_pressure_systolic"]).to eq("42.0")
    expect(read_back["blood_pressure_diastolic"]).to eq("42.0")
  end

  it "raises InvalidComposition for garbage JSON" do
    expect { described_class.call(template, "not json") }
      .to raise_error(described_class::InvalidComposition)
  end

  # skoba/anlage#39: 埋め込み CLUSTER 一段（#38 で保存できる形）の値も読み戻す
  it "埋め込み CLUSTER 配下の値（LabResultReport の分析名・数値）を読み戻す" do
    lab = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read)
    json = build_composition_json(lab, {
      "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => "空腹時血糖",
      "laboratory_test_analyte_at0001" => "98", "laboratory_test_analyte_at0001__units" => "mg/dL"
    })

    read_back = described_class.call(lab, json)

    expect(read_back).to eq(
      "laboratory_test_result_at0005" => "血液検査",
      "laboratory_test_analyte_at0024" => "空腹時血糖",
      "laboratory_test_analyte_at0001" => "98.0"
    )
  end
end
