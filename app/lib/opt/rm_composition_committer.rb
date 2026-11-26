module Opt
  # Builds a Composition from submitted values and commits its canonical
  # representation to the authoritative RM graph used by AQL.
  class RmCompositionCommitter
    Result = Data.define(:uid, :composition, :canonical_hash)

    # 撤去条件: openehr-rails側 RESERVED_KEYS 拡張（docs/upstream-candidates.md 9項のIssue化・解消）後
    NON_STRUCTURAL_ENTRY_KEYS = %w[language encoding subject].freeze

    # ehr: いまの患者の EHR（OpenehrRails::Rm::Ehr、skoba/anlage#136）。nil なら EHR に結び付けない
    # uid: 修正のとき、元の記録の uid（skoba/anlage#138）。同じ uid の commit で、gem の committer が版を 1 つ足す。nil なら新しい記録
    # recorded_at: 記録日時（skoba/anlage#144。サンプルデータの記録日）。nil なら保存した時刻。
    #   OBSERVATION のイベント時刻・履歴の起点と、新しい記録の context/start_time に入る
    # ブロック: commit の前に canonical を書き換える（サンプルデータの ICD-11 コード付きの傷病名。Demo::SampleCompositions）
    def self.call(template, values, ehr: nil, uid: nil, recorded_at: nil, &edit)
      new(template, values, ehr: ehr, uid: uid, recorded_at: recorded_at).call(&edit)
    end

    def initialize(template, values, ehr: nil, uid: nil, recorded_at: nil)
      @template = template
      @values = values
      @ehr = ehr
      @uid = uid
      @recorded_at = recorded_at || Time.current
    end

    def call
      rm_composition = Opt::CompositionBuilder.new(@template, @values, recorded_at: @recorded_at).build
      canonical_hash = JSON.parse(
        OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize
      )
      yield canonical_hash if block_given?
      committable_hash = canonical_hash.deep_dup
      remove_non_structural_entry_keys(committable_hash)

      uid = @uid || SecureRandom.uuid
      composition = OpenehrRails::Rm::CompositionCommitter.commit(committable_hash, uid: uid, ehr: @ehr, owner: nil,
                                                                  context_start_time: context_start_time)

      Result.new(uid:, composition:, canonical_hash:)
    end

    private

    # COMPOSITION の context/start_time（紹介日など。skoba/anlage#146）。新しい記録は保存した時刻
    # （docs/design/rm-attributes-without-inputs.md 2 節の規則 4）。修正（同じ uid の新しい版）は元の記録の時刻を引き継ぐ。
    # setting は渡さない（OPT に制約が無く、anlage では決めない。gem が組む）
    def context_start_time
      head = @uid && OpenehrRails::Rm::Composition.latest.find_by(uid: @uid)
      head&.context_start_time || @recorded_at
    end

    # SECTION は items を辿って、配下の ENTRY からも外す（skoba/anlage#80）
    def remove_non_structural_entry_keys(canonical_hash)
      strip_entries(canonical_hash.fetch("content"))
    end

    def strip_entries(content_items)
      content_items.each do |item|
        next strip_entries(item.fetch("items", [])) if item["_type"] == "SECTION"

        NON_STRUCTURAL_ENTRY_KEYS.each { |key| item.delete(key) }
      end
    end
  end
end
