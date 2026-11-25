module QueryBuilder
  # 版をまたいで引く（docs/design/s2-cross-version-plan.md 4 節、skoba/anlage#154）。選ばれたカードを、対応のある版ごとのカードに
  # 置き換えた選択の列を返す。AQL を組むのは Builder、実行するのは Runner。
  # 対応の無い項目が 1 つでもあれば組まない（ID が似ているだけの項目を、まとめて引かない）。
  class CrossVersion
    Selection = Struct.new(:archetype_id, :columns, :conditions, keyword_init: true)

    def self.selections(columns:, conditions:, mappings:, corpus:)
      new(columns, conditions, mappings, corpus).selections
    end

    def initialize(columns, conditions, mappings, corpus)
      @columns = Array(columns)
      @conditions = Array(conditions)
      @mappings = mappings
      @corpus = corpus
    end

    def selections
      cards = @columns + @conditions.flat_map { |condition| cards_of(condition) }
      raise Builder::InvalidSelection, "表示する項目が 1 つも無い" if @columns.empty?

      unmapped = cards.reject { |card| @mappings.archetype_ids(card) }.uniq
      if unmapped.any?
        raise Builder::InvalidSelection, "版の対応が無い項目がある: #{unmapped.map { |card| describe(card) }.join('、')}"
      end

      # 選ばれたカードすべての対応に共通で、索引にその版のカードがある版
      archetype_ids = cards.map { |card| @mappings.archetype_ids(card) }.reduce(:&)
      archetype_ids = archetype_ids.select { |archetype_id| cards.all? { |card| sibling(card, archetype_id) } }
      archetype_ids.sort_by { |archetype_id| archetype_id[/\.v(\d+)\z/, 1].to_i }.map do |archetype_id|
        Selection.new(archetype_id: archetype_id, columns: @columns.map { |card| sibling(card, archetype_id) },
                      conditions: @conditions.map { |condition| replace(condition, archetype_id) })
      end
    end

    private

    def cards_of(condition)
      condition.key?(:any) ? Array(condition[:any]).flat_map { |member| cards_of(member) } : [ condition.fetch(:card) ]
    end

    def replace(condition, archetype_id)
      return { any: Array(condition[:any]).map { |member| replace(member, archetype_id) } } if condition.key?(:any)

      condition.merge(card: sibling(condition.fetch(:card), archetype_id))
    end

    # その版の、同じ at-code のカード（索引に無ければ nil）。パスと型が同じことは、対応の行のレビューで確かめてある
    def sibling(card, archetype_id)
      @corpus.cards.find do |candidate|
        candidate.fetch("identity").values_at("archetype_id", "at_code") == [ archetype_id, card.dig("identity", "at_code") ]
      end
    end

    def describe(card)
      label = Array(card.dig("semantics", "labels")).first&.fetch("text", nil) || card.dig("identity", "at_code")
      "#{label}（#{card.fetch('identity').values_at('archetype_id', 'at_code').join(' ')}）"
    end
  end
end
