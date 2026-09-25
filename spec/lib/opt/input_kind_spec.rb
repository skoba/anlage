require "rails_helper"

# skoba/anlage#33 裁定 A: input_kind は登録時に一度だけ導出する唯一の方針属性。
# rm_type はモデルの事実として保持し、view／validator／builder は input_kind を読むだけ。
RSpec.describe Opt::InputKind do
  def kind(field, alternatives = nil)
    described_class.for(field, alternatives || [ field["rm_type"] ])
  end

  it "code_list を持つ DV_CODED_TEXT は select" do
    expect(kind({ "rm_type" => "DV_CODED_TEXT", "code_list" => %w[at0074], "value_set_uri" => nil })).to eq("select")
  end

  it "code_list が空・value_set_uri のみで DV_TEXT 代替があれば coded_free" do
    field = { "rm_type" => "DV_CODED_TEXT", "code_list" => [], "value_set_uri" => "terminology:http://id.who.int/icd/release/11/mms" }

    expect(kind(field, [ "DV_TEXT", "DV_CODED_TEXT" ])).to eq("coded_free")
  end

  it "code_list が空で DV_TEXT 代替が無ければ coded_manual（コード化必須・用語サービス未接続）" do
    field = { "rm_type" => "DV_CODED_TEXT", "code_list" => [], "value_set_uri" => "terminology:http://id.who.int/icd/release/11/mms" }

    expect(kind(field, [ "DV_CODED_TEXT" ])).to eq("coded_manual")
  end

  it "DV_QUANTITY／DV_COUNT は number、それ以外は text" do
    expect(kind({ "rm_type" => "DV_QUANTITY" })).to eq("number")
    expect(kind({ "rm_type" => "DV_COUNT" })).to eq("number")
    expect(kind({ "rm_type" => "DV_TEXT" })).to eq("text")
    expect(kind({ "rm_type" => "DV_DATE_TIME" })).to eq("text")
  end
end
