module Opt
  # 修正できる記録の判定（skoba/anlage#138、docs/design/m3-plan.md 7.3 P4）。
  # 記録の原本（canonical の Hash）を読み戻して（Opt::CompositionReader）組み直し（Opt::CompositionBuilder）、
  # content が原本と同じときだけ修正できる。読み戻せない形（Issue #30 の残り: INSTRUCTION、多段の CLUSTER、
  # 同じアーキタイプの 2 つめの ENTRY など）を含む記録を修正すると、値を黙って落とすので、修正させない。
  # 判定の規則を reader・builder と二重に持たないための往復の比較（Opt::FormCapability のドライランと同じ考え方）
  class CompositionEditability
    def self.editable?(template, canonical_hash)
      values = Opt::CompositionReader.call(template, JSON.generate(canonical_hash))
      # 記録した時刻（イベント時刻・履歴の起点）は入力ではない。原本の時刻で組み直して比べる（skoba/anlage#171）
      rebuilt = Opt::CompositionBuilder.new(template, values, recorded_at: Opt::RecordedTime.of(canonical_hash) || Time.current).build
      JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(rebuilt).serialize)["content"] == canonical_hash["content"]
    rescue Opt::CompositionReader::InvalidComposition, ArgumentError, KeyError, NoMethodError, TypeError
      false
    end
  end
end
