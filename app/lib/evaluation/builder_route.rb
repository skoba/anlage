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
      aql = QueryBuilder::Builder.build(
        columns: Array(selection[:columns]).map { |ref| card(ref) },
        conditions: Array(selection[:conditions]).map { |condition| condition.merge(card: card(condition.fetch(:card))) },
        composition_name: selection[:composition_name] ? true : false
      )
      lint = QueryBuilder::Linter.lint(aql, corpus: @corpus)
      return unbuildable(lint.findings.select(&:error?).map(&:message).join("／"), aql: aql) unless lint.ok?

      scored = AqlScorer.score(@question, aql: aql)
      Score.new(status: scored.status, aql: aql, missing: scored.missing, extra: scored.extra, error: scored.error)
    rescue QueryBuilder::Builder::InvalidSelection, CardNotFound => e
      unbuildable(e.message)
    end

    private

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
