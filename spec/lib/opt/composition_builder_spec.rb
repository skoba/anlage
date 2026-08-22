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
  end
end
