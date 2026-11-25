module Opt
  # Builds a Composition from submitted values and commits its canonical
  # representation to the authoritative RM graph used by AQL.
  class RmCompositionCommitter
    Result = Data.define(:uid, :composition, :canonical_hash)

    # 撤去条件: openehr-rails側 RESERVED_KEYS 拡張（docs/upstream-candidates.md 9項のIssue化・解消）後
    NON_STRUCTURAL_ENTRY_KEYS = %w[language encoding subject].freeze

    # ehr: いまの患者の EHR（OpenehrRails::Rm::Ehr、skoba/anlage#136）。nil なら EHR に結び付けない
    # uid: 修正のとき、元の記録の uid（skoba/anlage#138）。同じ uid の commit で、gem の committer が版を 1 つ足す。nil なら新しい記録
    def self.call(template, values, ehr: nil, uid: nil)
      new(template, values, ehr: ehr, uid: uid).call
    end

    def initialize(template, values, ehr: nil, uid: nil)
      @template = template
      @values = values
      @ehr = ehr
      @uid = uid
    end

    def call
      rm_composition = Opt::CompositionBuilder.new(@template, @values).build
      canonical_hash = JSON.parse(
        OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize
      )
      committable_hash = canonical_hash.deep_dup
      remove_non_structural_entry_keys(committable_hash)

      uid = @uid || SecureRandom.uuid
      composition = OpenehrRails::Rm::CompositionCommitter.commit(committable_hash, uid: uid, ehr: @ehr, owner: nil)

      Result.new(uid:, composition:, canonical_hash:)
    end

    private

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
