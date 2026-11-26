module Evaluation
  # S2 の経路（docs/design/s1-eval-v2-plan.md 8 節）。aql の問いの selection（クエリビルダーへの入力）から AQL を組み、
  # 参照 AQL と同じ採点器（AqlScorer。期待行との照合）に通す。組めないもの（索引に無いカード、ビルダーが拒む選択、
  # リンタの error）は例外で止めず unbuildable に数える。
  class BuilderRoute
    Score = Struct.new(:status, :aql, :missing, :extra, :error, keyword_init: true)

    class CardNotFound < StandardError; end

    def self.score(question, corpus: QueryBuilder::Corpus.active)
      return nil unless question.selection

      new(question, corpus).score
    end

    def initialize(question, corpus)
      @question = question
      @corpus = corpus
    end

    def score
      selection = @question.selection
      columns = Array(selection[:columns]).map { |ref| card(ref) }
      conditions = Array(selection[:conditions]).map { |condition| resolve(condition) }
      return score_across_versions(columns, conditions, selection) if selection[:across_versions]

      aql = QueryBuilder::Builder.build(columns: columns, conditions: conditions,
                                        template_id: selection[:template_id] ? true : false)
      lint = QueryBuilder::Linter.lint(aql, corpus: @corpus)
      return unbuildable(lint.findings.select(&:error?).map(&:message).join("／"), aql: aql) unless lint.ok?

      scored = AqlScorer.score(@question, aql: aql)
      Score.new(status: scored.status, aql: aql, missing: scored.missing, extra: scored.extra, error: scored.error)
    rescue QueryBuilder::Builder::InvalidSelection, CardNotFound => e
      unbuildable(e.message)
    end

    private

    # 版をまたぐ問い（docs/design/s1-eval-v2-plan.md 8.5）: 対応の表で版ごとの AQL を組み、行の先頭にアーキタイプの ID を足して採点する
    def score_across_versions(columns, conditions, selection)
      aqls = QueryBuilder::CrossVersion.selections(columns: columns, conditions: conditions, corpus: @corpus,
                                                   mappings: QueryBuilder::VersionMappings.default).to_h do |version|
        [ version.archetype_id, QueryBuilder::Builder.build(columns: version.columns, conditions: version.conditions,
                                                            template_id: selection[:template_id] ? true : false) ]
      end
      text = aqls.values.join("\n\n")
      errors = aqls.values.flat_map { |aql| QueryBuilder::Linter.lint(aql, corpus: @corpus).findings.select(&:error?) }
      return unbuildable(errors.map(&:message).join("／"), aql: text) if errors.any?

      scored = AqlScorer.score(@question, aqls: aqls)
      Score.new(status: scored.status, aql: text, missing: scored.missing, extra: scored.extra, error: scored.error)
    end

    # 条件のカードの参照を、索引のカードに置き換える。どちらかを満たす（any）は中の条件も置き換える
    def resolve(condition)
      return { any: Array(condition[:any]).map { |member| resolve(member) } } if condition.key?(:any)

      condition.merge(card: card(condition.fetch(:card)))
    end

    # {archetype_id, at_code} に当たる最初のカード。同じアーキタイプが複数のテンプレートにあっても、ビルダーが組む AQL は同じ形になる
    def card(ref)
      @corpus.cards.find { |card| card.fetch("identity").values_at("archetype_id", "at_code") == ref.values_at(:archetype_id, :at_code) } ||
        raise(CardNotFound, "索引にカードが無い: #{ref[:archetype_id]} #{ref[:at_code]}")
    end

    def unbuildable(message, aql: nil)
      Score.new(status: :unbuildable, aql: aql, missing: [], extra: [], error: message)
    end
  end
end
