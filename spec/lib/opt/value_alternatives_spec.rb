require "rails_helper"

# skoba/anlage#33（解決形 (a)）: gem の FieldExtractor は代替制約のうち C_CODE_REFERENCE
# 側を主型に選び、DV_TEXT 代替の存在を field に載せない。Anlage 側で OPT を走査し、
# field の path をキーに代替 RM 型の一覧を得る（PathcardExtractor#value_attribute_children
# と同じ規則、path 書式も同じ）。
RSpec.describe Opt::ValueAlternatives do
  def alternatives_for(fixture)
    described_class.call(Opt::SafeParser.parse(Rails.root.join("spec/fixtures/opt/#{fixture}").read))
  end

  it "ProblemList の傷病名 at0002 は [DV_TEXT, DV_CODED_TEXT]、診断確度 at0073 は [DV_CODED_TEXT, DV_TEXT]（OPT 出現順）を返す" do
    alternatives = alternatives_for("ProblemList.opt")

    expect(alternatives.fetch("/content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0002]/value"))
      .to eq([ "DV_TEXT", "DV_CODED_TEXT" ])
    expect(alternatives.fetch("/content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0073]/value"))
      .to eq([ "DV_CODED_TEXT", "DV_TEXT" ])
  end

  it "SECTION 配下（jp_referral）でも FieldExtractor と同じ path で引ける" do
    alternatives = alternatives_for("jp_referral.opt")

    expect(alternatives.fetch("/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0002]/value"))
      .to eq([ "DV_TEXT", "DV_CODED_TEXT" ])
  end
end
