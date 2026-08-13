require "rails_helper"

RSpec.describe Opt::FormValidator do
  # A synthetic template double, since the only local fixture
  # (patient_blood_pressure.opt) happens to have no required fields --
  # the required/coded-text branches need constraints not present there.
  FakeTemplate = Struct.new(:fields)

  let(:template) do
    FakeTemplate.new([
      { "name" => "systolic", "rm_type" => "DV_QUANTITY", "required" => true, "magnitude_range" => [ 0.0, 300.0 ] },
      { "name" => "cuff_size", "rm_type" => "DV_CODED_TEXT", "required" => false, "code_list" => %w[small medium large] }
    ])
  end

  it "is valid when required fields are present and values satisfy constraints" do
    result = described_class.call(template, "systolic" => "120", "cuff_size" => "medium")
    expect(result).to be_valid
  end

  it "flags a missing required field" do
    result = described_class.call(template, "cuff_size" => "medium")
    expect(result).not_to be_valid
    expect(result.errors["systolic"]).to be_present
  end

  it "does not flag an absent optional field" do
    result = described_class.call(template, "systolic" => "120")
    expect(result.errors).not_to have_key("cuff_size")
  end

  it "flags a value below the magnitude range" do
    result = described_class.call(template, "systolic" => "-1", "cuff_size" => "medium")
    expect(result.errors["systolic"]).to be_present
  end

  it "flags a value above the magnitude range" do
    result = described_class.call(template, "systolic" => "301", "cuff_size" => "medium")
    expect(result.errors["systolic"]).to be_present
  end

  it "flags a non-numeric value for a quantity field" do
    result = described_class.call(template, "systolic" => "abc", "cuff_size" => "medium")
    expect(result.errors["systolic"]).to be_present
  end

  it "flags a coded-text value outside the allowed code list" do
    result = described_class.call(template, "systolic" => "120", "cuff_size" => "extra-large")
    expect(result.errors["cuff_size"]).to be_present
  end
end
