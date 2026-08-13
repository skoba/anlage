require "rails_helper"

RSpec.describe Opt::TemplateDiff do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }
  let(:old_template) { Template.build_from_opt_xml(opt_xml) }

  it "reports no changes for identical content" do
    result = described_class.call(old_template, Template.build_from_opt_xml(opt_xml))
    expect(result.any_changes?).to eq(false)
  end

  it "reports a changed field when a label in the OPT differs" do
    mutated_xml = opt_xml.sub("Systolic", "Systolic Pressure")
    new_template = Template.build_from_opt_xml(mutated_xml)

    result = described_class.call(old_template, new_template)

    expect(result.any_changes?).to eq(true)
    expect(result.changed.size).to eq(1)
    expect(result.changed.first["before"]["label"]).to eq("Systolic")
    expect(result.changed.first["after"]["label"]).to eq("Systolic Pressure")
    expect(result.added).to be_empty
    expect(result.removed).to be_empty
  end
end
