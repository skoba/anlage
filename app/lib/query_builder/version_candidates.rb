module QueryBuilder
  # アーキタイプの版の対応の候補（docs/design/s2-cross-version-plan.md 3.1）。active のカードから、
  # アーキタイプの ID（版を除く）・at-code・パス・RM の型がすべて一致する項目の組を挙げる。
  # 候補は「同じものかもしれない」までで、問い合わせには使わない（使うのは VersionMappings の active の行だけ）。
  class VersionCandidates
    VERSION = /\.(v\d+)\z/
    Candidate = Struct.new(:concept, :at_code, :path, :rm_type, :versions, :labels, :differences, keyword_init: true)

    def self.call(corpus)
      new(corpus).call
    end

    # 版（末尾の .v<数字>）を除いたアーキタイプの ID と、版
    def self.split(archetype_id)
      version = archetype_id.to_s[VERSION, 1]
      version ? [ archetype_id.sub(VERSION, ""), version ] : [ archetype_id.to_s, nil ]
    end

    def initialize(corpus)
      @corpus = corpus
    end

    def call
      groups = @corpus.cards.group_by { |card| key(card) }.reject { |group_key, _| group_key.nil? }
      groups.filter_map do |(concept, at_code, path, rm_type), cards|
        by_version = cards.group_by { |card| self.class.split(card.dig("identity", "archetype_id")).last }.transform_values(&:first)
        next if by_version.size < 2

        versions = by_version.keys.sort_by { |version| version.delete("v").to_i }
        Candidate.new(concept: concept, at_code: at_code, path: path, rm_type: rm_type, versions: versions,
                      labels: versions.index_with { |version| label(by_version.fetch(version)) },
                      differences: differences(versions, by_version))
      end.sort_by { |candidate| [ candidate.concept, candidate.at_code, candidate.path ] }
    end

    private

    # [版を除いたアーキタイプの ID, at-code, そのアーキタイプのルートから下のパス, RM の型]。版の無い ID のカードは候補にしない
    def key(card)
      archetype_id = card.dig("identity", "archetype_id").to_s
      concept, version = self.class.split(archetype_id)
      return nil unless version

      [ concept, card.dig("identity", "at_code"), relative_path(card, archetype_id), card.dig("semantics", "rm_type") ]
    end

    # 途中の埋め込みアーキタイプの述語は、版を除いて比べる
    def relative_path(card, archetype_id)
      segments = card.dig("identity", "path").to_s.split("/").reject(&:empty?)
      index = segments.rindex { |segment| segment.end_with?("[#{archetype_id}]") }
      segments[((index || -1) + 1)..].map { |segment| segment.sub(/\.v\d+\]\z/, "]") }.join("/")
    end

    def label(card)
      Array(card.dig("semantics", "labels")).first&.fetch("text", nil)
    end

    COMPARED = { "単位" => ->(value) { value["units"] },
                 "値の範囲" => ->(value) { value["magnitude_range"]&.values_at("lower", "upper", "lower_included", "upper_included") },
                 "値集合" => ->(value) { Array(value["code_list"]).map { |entry| entry["code"] }.sort.presence } }.freeze

    def differences(versions, by_version)
      COMPARED.filter_map do |name, reader|
        values = versions.map { |version| reader.call(by_version.fetch(version).dig("constraints", "value") || {}) }
        next if values.uniq.size == 1

        "#{name}（#{versions.zip(values).map { |version, value| "#{version}: #{describe(value)}" }.join('、')}）"
      end
    end

    def describe(value)
      value.nil? ? "なし" : Array(value).join("／")
    end
  end
end
