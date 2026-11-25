module Opt
  # 修正できる記録の判定（skoba/anlage#138、docs/design/m3-plan.md 7.3 P4）。
  # 記録の原本（canonical の Hash）を読み戻して（Opt::CompositionReader）組み直し（Opt::CompositionBuilder）、
  # content が原本と同じときだけ修正できる。読み戻せない形（Issue #30 の残り: INSTRUCTION、多段の CLUSTER、
  # 同じアーキタイプの 2 つめの ENTRY など）を含む記録を修正すると、値を黙って落とすので、修正させない。
  # 判定の規則を reader・builder と二重に持たないための往復の比較（Opt::FormCapability のドライランと同じ考え方）
  class CompositionEditability
    def self.editable?(template, canonical_hash)
      values = Opt::CompositionReader.call(template, JSON.generate(canonical_hash))
      rebuilt = Opt::CompositionBuilder.new(template, values).build
      JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(rebuilt).serialize)["content"] == canonical_hash["content"]
    rescue Opt::CompositionReader::InvalidComposition, ArgumentError, KeyError, NoMethodError, TypeError
      false
    end
  end
end
