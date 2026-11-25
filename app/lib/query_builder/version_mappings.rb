module QueryBuilder
  # アーキタイプの版の対応の表（docs/design/s2-cross-version-plan.md 3.2）。表（config/version_mappings.yml）が供給するのは
  # 「この版とこの版の、この項目は同じもの」だけ。パス・型・単位は OPT から取ったカードのものを使う。
  # 問い合わせに使うのは active の行（人間がレビューした行）だけで、pending の行（候補）は読むが使わない。
  class VersionMappings
    class InvalidTable < StandardError; end

    PATH = "config/version_mappings.yml".freeze
    STATUSES = %i[active pending].freeze

    Row = Struct.new(:concept, :at_code, :versions, :status, :note, :source, :reviewed_by, :reviewed_at, keyword_init: true) do
      def active? = status == :active
      def archetype_ids = versions.map { |version| "#{concept}.#{version}" }
    end

    def self.default
      @default ||= load(Rails.root.join(PATH))
    end

    def self.reset!
      @default = nil
    end

    def self.load(path)
      new(Array(YAML.load_file(path, permitted_classes: [ Date ])))
    end

    def self.none
      new([])
    end

    attr_reader :rows

    def initialize(entries)
      @rows = entries.map { |entry| build(entry) }
      duplicated = @rows.group_by { |row| [ row.concept, row.at_code ] }.select { |_, rows| rows.size > 1 }.keys
      raise InvalidTable, "同じ項目の行が 2 つ以上ある（#{duplicated.map { |key| key.join(' ') }.join('、')}）" if duplicated.any?

      @active = @rows.select(&:active?).index_by { |row| [ row.concept, row.at_code ] }
    end

    # カードの項目と同じものと確かめた版のアーキタイプ ID（カード自身の版を含む）。対応の行が無い、行にカードの版が無いときは nil
    def archetype_ids(card)
      concept, version = VersionCandidates.split(card.dig("identity", "archetype_id"))
      row = @active[[ concept, card.dig("identity", "at_code") ]]
      row.archetype_ids if row && row.versions.include?(version)
    end

    private

    def build(entry)
      concept = entry["concept"].to_s.strip
      raise InvalidTable, "concept（版を除いたアーキタイプの ID）の無い行がある（#{entry.inspect}）" if concept.empty?

      name = "#{concept} #{entry['at_code']}"
      raise InvalidTable, "#{name}: at_code が無い" if entry["at_code"].blank?

      status = entry.fetch("status", "active").to_s.to_sym
      raise InvalidTable, "#{name}: status は #{STATUSES.join('／')} のどれか（#{entry['status'].inspect}）" unless STATUSES.include?(status)

      versions = Array(entry["versions"]).map(&:to_s)
      unless versions.uniq.size >= 2 && versions.all? { |version| version.match?(/\Av\d+\z/) }
        raise InvalidTable, "#{name}: versions は v1・v2 のように、2 つ以上の版を書く（#{entry['versions'].inspect}）"
      end

      required = status == :active ? %w[source reviewed_by reviewed_at] : %w[source]
      missing = required.reject { |key| entry[key].present? }
      raise InvalidTable, "#{name}: #{missing.join('・')} が無い" if missing.any?

      Row.new(concept: concept, at_code: entry["at_code"], versions: versions, status: status, note: entry["note"],
              source: entry["source"], reviewed_by: entry["reviewed_by"], reviewed_at: entry["reviewed_at"])
    end
  end
end
