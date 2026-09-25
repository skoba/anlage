require "rails_helper"

RSpec.describe Opt::FormValidator do
  # A synthetic template double, since the only local fixture
  # (patient_blood_pressure.opt) happens to have no required fields --
  # the required/coded-text branches need constraints not present there.
  FakeTemplate = Struct.new(:fields)

  let(:template) do
    FakeTemplate.new([
      { "name" => "systolic", "rm_type" => "DV_QUANTITY", "input_kind" => "number", "required" => true, "magnitude_range" => [ 0.0, 300.0 ] },
      { "name" => "cuff_size", "rm_type" => "DV_CODED_TEXT", "input_kind" => "select", "required" => false, "code_list" => %w[small medium large] }
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

# skoba/anlage#33 裁定 B: coded_manual（コード化必須・用語サービス未接続）で code 未入力は
# validation error。raw 文字列を code に詰めた DvCodedText は存在しないコードの捏造。
RSpec.describe Opt::FormValidator, "#33 input_kind" do
  let(:template) do
    Template.new(template_id: "t", web_template: { "template_id" => "t", "entries" => [ { "archetype_id" => "a", "fields" => fields } ] })
  end
  let(:fields) do
    [
      { "name" => "dx", "rm_type" => "DV_CODED_TEXT", "input_kind" => "coded_manual", "code_list" => [], "value_set_uri" => "terminology:http://id.who.int/icd/release/11/mms", "required" => false },
      { "name" => "free", "rm_type" => "DV_CODED_TEXT", "input_kind" => "coded_free", "code_list" => [], "value_set_uri" => "terminology:x", "required" => false }
    ]
  end

  it "coded_manual は値があって code が無ければエラー（用語サービス未接続のため system/code 手入力）" do
    result = described_class.call(template, { "dx" => "2型糖尿病" })

    expect(result.errors["dx"]).to include("コード入力が必要")
  end

  it "coded_manual は code があれば通る" do
    expect(described_class.call(template, { "dx" => "2型糖尿病", "dx__code" => "5A11", "dx__system" => "http://id.who.int/icd/release/11/mms" })).to be_valid
  end

  it "coded_free は自由記載で通る" do
    expect(described_class.call(template, { "free" => "自由記載" })).to be_valid
  end
end
