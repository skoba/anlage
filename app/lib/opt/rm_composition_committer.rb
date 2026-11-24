module Opt
  # Builds a Composition from submitted values and commits its canonical
  # representation to the authoritative RM graph used by AQL.
  class RmCompositionCommitter
    Result = Data.define(:uid, :composition, :canonical_hash)

    # 撤去条件: openehr-rails側 RESERVED_KEYS 拡張（docs/upstream-candidates.md 9項のIssue化・解消）後
    NON_STRUCTURAL_ENTRY_KEYS = %w[language encoding subject].freeze

    def self.call(template, values)
      new(template, values).call
    end

    def initialize(template, values)
      @template = template
      @values = values
    end

    def call
      rm_composition = Opt::CompositionBuilder.new(@template, @values).build
      canonical_hash = JSON.parse(
        OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize
      )
      committable_hash = canonical_hash.deep_dup
      remove_non_structural_entry_keys(committable_hash)

      uid = SecureRandom.uuid
      composition = OpenehrRails::Rm::CompositionCommitter.commit(committable_hash, uid: uid, owner: nil)

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
