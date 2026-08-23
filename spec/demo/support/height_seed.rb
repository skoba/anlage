# 実パイプライン駆動（案A、docs/design/demo-queries-plan.md 2節）。
# Opt::CompositionBuilder（フォーム保存経路と同じRM構築ロジック）で
# Compositionを組み立て、OpenEHR::Serializer::RMJSONSerializerでcanonical
# JSONへシリアライズし、OpenehrRails::Rm::CompositionCommitter経由で
# AQLが参照するRMグラフへ投入する。
#
# 既知の回避策2点（docs/reports/demo-queries-log.md R3で発見・記録）:
#
# 1. Opt::CompositionBuilder はENTRY（OBSERVATION等）に archetype_details
#    を設定しない（archetype_node_id のみ）。OpenehrRails::Rm::EntryNode は
#    archetype_id の presence を検証するため、GraphBuilder が
#    hash.dig('archetype_details', 'archetype_id', 'value') を読めるよう
#    ここで補完する。恒久対応は Opt::CompositionBuilder 側の課題として
#    Issue化済み（skoba/anlage#9）。
# 2. RMJSONSerializer が出力するENTRY hashには language/encoding/subject
#    （いずれもcanonical RM上は正当な属性）が含まれるが、
#    OpenehrRails::Rm::GraphBuilder::RESERVED_KEYS がこれらを除外対象に
#    含んでおらず、構造ノードとして誤って解釈されクラッシュする
#    （"unknown RM node type CODE_PHRASE"等）。ここで削除して回避する。
#    gem側の課題としてdocs/upstream-candidates.mdへ観察を追記済み（9項）。
module HeightSeed
  module_function

  # GraphBuilder::RESERVED_KEYS に含まれないENTRY属性で、AQLクエリが
  # 参照しない（=このデモの範囲では欠落させても実害がない）もの。
  # 撤去条件: openehr-rails側 RESERVED_KEYS 拡張（docs/upstream-candidates.md 9項のIssue化・解消）後
  NON_STRUCTURAL_ENTRY_KEYS = %w[language encoding subject].freeze

  def template
    @template ||= begin
      existing = Template.find_by(template_id: "bmi_calculation")
      existing || Template.build_from_opt_xml(
        Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read
      ).tap(&:save!)
    end
  end

  def seed!(height_cm)
    values = {
      "height" => height_cm.to_s,
      "body_weight" => "70.0",
      "body_mass_index" => "21.6",
      "body_mass_index_at0013" => "normal"
    }

    rm_composition = Opt::CompositionBuilder.new(template, values).build
    hash = JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize)

    hash["content"].each do |content_hash|
      NON_STRUCTURAL_ENTRY_KEYS.each { |key| content_hash.delete(key) }
    end

    OpenehrRails::Rm::CompositionCommitter.commit(hash, uid: SecureRandom.uuid, owner: nil)
  end
end
