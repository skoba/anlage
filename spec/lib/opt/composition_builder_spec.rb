require "rails_helper"

RSpec.describe Opt::CompositionBuilder do
  describe "日本語前提の既定値" do
    # 実物fixture: Archetype Designerからlang=jaでエクスポートしたOPT
    # (openEHR-EHR-COMPOSITION.encounter.v1 + openEHR-EHR-OBSERVATION.blood_pressure.v2)。
    # 登録OPTはlang=ja前提とする方針 (docs/design/pathcards-language-policy.md)
    # に合わせ、保存されるCompositionの既定言語・地域もja/JPであることを仕様として固定する。
    let(:source_xml) { Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read }

    # 保存→reloadでweb_templateをJSON往復させ、本番経路(登録済みテンプレート)と
    # 同じ文字列キー状態にする
    let(:template) { Template.build_from_opt_xml(source_xml).tap(&:save!).reload }

    # CompositionBuilderは全フィールドの値を要求する(@values.fetch)ため、
    # rm_typeごとの妥当なサンプル値を全フィールドに供給する
    let(:values) do
      samples = {
        "DV_QUANTITY" => "120",
        "DV_COUNT" => "1",
        "DV_BOOLEAN" => "true",
        "DV_DATE" => "2026-08-21",
        "DV_DATE_TIME" => "2026-08-21T10:00:00+09:00"
      }
      template.fields.to_h { |field| [ field["name"], samples.fetch(field["rm_type"], "テキスト") ] }
    end

    let(:composition) { described_class.new(template, values).build }

    it "Compositionのlanguageはja (ISO_639-1) になる" do
      expect(composition.language.code_string).to eq("ja")
    end

    it "CompositionのterritoryはJP (ISO_3166-1) になる" do
      expect(composition.territory.code_string).to eq("JP")
    end

    describe "ENTRYのarchetype_details" do
      let(:entry) { template.entries.first }
      let(:built_entry) { composition.content.first }

      it "archetype_id、template_id、RM versionを設定する" do
        expect(built_entry.archetype_details.archetype_id.value).to eq(entry["archetype_id"])
        expect(built_entry.archetype_details.template_id.value).to eq(template.web_template["template_id"])
        expect(built_entry.archetype_details.rm_version).to eq(described_class::RM_VERSION)
      end
    end
  end
end

# skoba/anlage#33: builder は input_kind を読むだけ。coded_free は DV_TEXT（OR 制約の
# 正規の一方）、coded_manual は手入力の system/code で DvCodedText。
RSpec.describe Opt::CompositionBuilder, "#33 input_kind" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload }
  let(:base_values) do
    { "problem_diagnosis_at0077" => "2026-03-01T00:00:00", "problem_diagnosis_at0003" => "2026-03-01T00:00:00",
      "problem_diagnosis_at0030" => "2026-03-01T00:00:00", "problem_diagnosis_at0073" => "at0074" }
  end

  def diagnosis_value(values)
    described_class.new(template, values).build.content.first.data.items.find { |item| item.archetype_node_id == "at0002" }.value
  end

  it "coded_free（ProblemList 傷病名）は DvText で保存する" do
    value = diagnosis_value(base_values.merge("problem_diagnosis_at0002" => "2型糖尿病"))

    expect(value).to be_a(OpenEHR::RM::DataTypes::Text::DvText)
    expect(value).not_to be_a(OpenEHR::RM::DataTypes::Text::DvCodedText)
    expect(value.value).to eq("2型糖尿病")
  end

  it "coded_manual は手入力の system/code で DvCodedText を組む" do
    field = template.fields.find { |f| f["name"] == "problem_diagnosis_at0002" }
    field["input_kind"] = "coded_manual"
    template.update_column(:web_template, template.web_template)
    template.reload

    value = diagnosis_value(base_values.merge("problem_diagnosis_at0002" => "2型糖尿病", "problem_diagnosis_at0002__code" => "5A11", "problem_diagnosis_at0002__system" => "http://id.who.int/icd/release/11/mms"))

    expect(value).to be_a(OpenEHR::RM::DataTypes::Text::DvCodedText)
    expect(value.defining_code.code_string).to eq("5A11")
    expect(value.defining_code.terminology_id.value).to eq("http://id.who.int/icd/release/11/mms")
  end
end
