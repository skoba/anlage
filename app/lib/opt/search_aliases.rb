module Opt
  # パスカード検索の別名表（docs/design/s3-search-plan.md 3.1、skoba/anlage#152）。
  # 表（config/search_aliases.yml）は人間がレビューした行だけを持つ。ここが供給するのは「問いの語 → カード」の対応付けだけで、
  # カードの意味・パス・制約は OPT から取ったものを変えない（LLM 分業原理と同じ線引き）。
  class SearchAliases
    class InvalidTable < StandardError; end

    PATH = "config/search_aliases.yml".freeze
    RELATIONS = %i[alias exclude].freeze
    STATUSES = %i[active pending].freeze
    REQUIRED = %w[source reviewed_by reviewed_at].freeze

    Row = Struct.new(:term, :relation, :status, :targets, :source, :reviewed_by, :reviewed_at, :pending_until, keyword_init: true) do
      def alias? = relation == :alias
      def exclude? = relation == :exclude
      def active? = status == :active

      # 対応先の何番めに当たるか（当たらなければ nil）。at_code の無い対応先は、そのアーキタイプのカードすべてに当たる
      def target_index(card)
        identity = card.fetch("identity")
        targets.index do |target|
          identity["archetype_id"] == target[:archetype_id] && (target[:at_code].nil? || identity["at_code"] == target[:at_code])
        end
      end
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

    # 語の照合に使う形: 前後の空白を取り、NFKC にそろえ、英字の大小を無視する
    def self.normalize(text)
      text.to_s.unicode_normalize(:nfkc).strip.downcase
    end

    attr_reader :rows

    def initialize(entries)
      @rows = entries.map { |entry| build(entry) }
      duplicated = @rows.group_by { |row| self.class.normalize(row.term) }.select { |_, rows| rows.size > 1 }.keys
      raise InvalidTable, "同じ語の行が 2 つ以上ある（#{duplicated.join('、')}）" if duplicated.any?

      @active = @rows.select(&:active?).index_by { |row| self.class.normalize(row.term) }
    end

    # 問いの全体が表の語と同じときだけ、その行を返す（部分一致では引かない）。保留の行は引かない
    def lookup(query)
      @active[self.class.normalize(query)]
    end

    # 検索に使っている語（保留でない行）
    def terms
      @rows.select(&:active?).map(&:term)
    end

    def include?(query) = !lookup(query).nil?

    private

    def build(entry)
      term = entry["term"].to_s.strip
      raise InvalidTable, "term（問いの語）の無い行がある（#{entry.inspect}）" if term.empty?

      missing = REQUIRED.reject { |key| entry[key].present? }
      raise InvalidTable, "#{term}: #{missing.join('・')} が無い" if missing.any?

      Row.new(term: term, relation: enum(term, "relation", entry["relation"], RELATIONS),
              status: enum(term, "status", entry.fetch("status", "active"), STATUSES), targets: targets(term, entry["targets"]),
              source: entry["source"], reviewed_by: entry["reviewed_by"], reviewed_at: entry["reviewed_at"],
              pending_until: entry["pending_until"])
    end

    def targets(term, list)
      targets = Array(list)
      raise InvalidTable, "#{term}: targets（対応先）が無い" if targets.empty?

      targets.map do |target|
        archetype_id = target.is_a?(Hash) ? target["archetype_id"].to_s : ""
        raise InvalidTable, "#{term}: targets に archetype_id が無い（#{target.inspect}）" if archetype_id.empty?

        { archetype_id: archetype_id, at_code: target["at_code"].presence }
      end
    end

    def enum(term, key, value, allowed)
      symbol = value.to_s.to_sym
      return symbol if allowed.include?(symbol)

      raise InvalidTable, "#{term}: #{key} は #{allowed.join('／')} のどれか（#{value.inspect}）"
    end
  end
end
