module Evaluation
  # card の問いの採点（docs/design/s1-eval-v2-plan.md 2.4）。
  # results は Opt::PathcardSearch.call の戻り値（スコア降順のカード配列）。
  class CardScorer
    K = 3

    Score = Struct.new(:rank, :hit_at_1, :hit_at_3, :recall_at_3, :reciprocal_rank, :complete_failure, :violations,
                       keyword_init: true)

    def self.score(question, results, k: K)
      new(question, results, k).score
    end

    def initialize(question, results, k)
      @question = question
      @results = results
      @k = k
    end

    def score
      rank = @results.index { |card| matches_any?(card, @question.expected) }
      top_k = @results.first(@k)
      found = @question.expected.count { |ref| top_k.any? { |card| matches?(card, ref) } }

      Score.new(
        rank: rank,
        hit_at_1: rank == 0,
        hit_at_3: !rank.nil? && rank < @k,
        recall_at_3: @question.expected.empty? ? 0.0 : found.fdiv(@question.expected.size),
        reciprocal_rank: rank ? 1.0 / (rank + 1) : 0.0,
        complete_failure: rank.nil?,
        violations: @question.forbidden.select { |ref| top_k.any? { |card| matches?(card, ref) } }
      )
    end

    private

    def matches_any?(card, refs)
      refs.any? { |ref| matches?(card, ref) }
    end

    # match: archetype（v1 互換）は archetype_id だけを見る。match: card は at_code も見るが、
    # 期待要素に at_code が無ければ archetype の一致で足りる。
    def matches?(card, ref)
      identity = card.fetch("identity")
      return false unless identity["archetype_id"] == ref[:archetype_id]
      return true if @question.match == :archetype || ref[:at_code].nil?

      identity["at_code"] == ref[:at_code]
    end
  end
end
