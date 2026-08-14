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
end
