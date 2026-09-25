require "rails_helper"

RSpec.describe Opt::FormValidator do
  # A synthetic template double, since the only local fixture
  # (patient_blood_pressure.opt) happens to have no required fields --
  # the required/coded-text branches need constraints not present there.
  FakeTemplate = Struct.new(:fields)

  let(:template) do
    FakeTemplate.new([
      { "name" => "systolic", "rm_type" => "DV_QUANTITY", "input_kind" => "number", "units" => "mm[Hg]", "required" => true, "magnitude_range" => [ 0.0, 300.0 ] },
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

# skoba/anlage#35: 日付・時刻の形式はローカルで検証する（不正値は 422 の説明に）
RSpec.describe Opt::FormValidator, "#35 日付・時刻の形式" do
  let(:template) do
    Template.new(template_id: "t", web_template: { "template_id" => "t", "entries" => [ { "archetype_id" => "a", "fields" => [
      { "name" => "dt", "label" => "発症日時", "rm_type" => "DV_DATE_TIME", "input_kind" => "datetime", "required" => false },
      { "name" => "d", "label" => "日付", "rm_type" => "DV_DATE", "input_kind" => "date", "required" => false },
      { "name" => "t", "label" => "時刻", "rm_type" => "DV_TIME", "input_kind" => "time", "required" => false }
    ] } ] })
  end

  it "YYYY-MM-DD と HH:MM を受け、それ以外は形式エラー" do
    expect(described_class.call(template, { "dt" => "2026-09-22", "dt__time" => "14:30", "d" => "2026-09", "t" => "09:05" })).to be_valid
    result = described_class.call(template, { "dt" => "2026/09/22", "d" => "22-09-2026", "t" => "9時" })
    expect(result.errors["dt"]).to include("日付の形式")
    expect(result.errors["d"]).to include("日付の形式")
    expect(result.errors["t"]).to include("時刻の形式")
  end

  it "時刻（任意）だけが不正なら日時の項目にエラーを付ける" do
    expect(described_class.call(template, { "dt" => "2026-09-22", "dt__time" => "14時30分" }).errors["dt"]).to include("時刻の形式")
  end
end

# skoba/anlage#37: 数値には単位が要る（リストが 1 つ以上あれば既定＝先頭、無ければ入力必須）
RSpec.describe Opt::FormValidator, "#37 単位" do
  def template_with(units_list)
    Template.new(template_id: "t", web_template: { "template_id" => "t", "entries" => [ { "archetype_id" => "a", "fields" => [
      { "name" => "q", "label" => "値", "rm_type" => "DV_QUANTITY", "input_kind" => "number", "units_list" => units_list, "required" => false }
    ] } ] })
  end

  it "units リストが無い要素は単位未入力でエラー、入力があれば通る" do
    expect(described_class.call(template_with([]), { "q" => "5.5" }).errors["q"]).to include("単位")
    expect(described_class.call(template_with([]), { "q" => "5.5", "q__units" => "mg/dL" })).to be_valid
  end

  it "units リストがあれば未入力でも通る（既定＝先頭）" do
    expect(described_class.call(template_with([ "kg/m2", "[lb_av]/[in_i]2" ]), { "q" => "21.6" })).to be_valid
  end
end
