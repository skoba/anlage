module Evaluation
  # card の問いの採点（docs/design/s1-eval-v2-plan.md 2.4）。
  # results は Opt::PathcardSearch.call の戻り値（スコア降順のカード配列）。
  class CardScorer
    K = 3

    # order_pairs: 順位が異なる期待要素の組の数。order_kept は組が無ければ nil（順位遵守の対象外）。
    # acceptables: top-k に出た許容（情報。hit にも負例違反にも数えない）。同 7 節
    Score = Struct.new(:rank, :hit_at_1, :hit_at_3, :recall_at_3, :reciprocal_rank, :complete_failure, :violations,
                       :order_pairs, :order_pairs_kept, :order_kept, :acceptables, keyword_init: true)

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
      pairs = order_pairs
      kept = pairs.count { |higher, lower| kept?(higher, lower) }

      Score.new(
        rank: rank,
        hit_at_1: rank == 0,
        hit_at_3: !rank.nil? && rank < @k,
        recall_at_3: @question.expected.empty? ? 0.0 : found.fdiv(@question.expected.size),
        reciprocal_rank: rank ? 1.0 / (rank + 1) : 0.0,
        complete_failure: rank.nil?,
        violations: @question.forbidden.select { |ref| top_k.any? { |card| matches?(card, ref) } },
        order_pairs: pairs.size,
        order_pairs_kept: kept,
        order_kept: pairs.empty? ? nil : kept == pairs.size,
        acceptables: @question.acceptable.select { |ref| top_k.any? { |card| matches?(card, ref) } }
      )
    end

    private

    # 順位が異なる期待要素の組（上位, 下位）。rank の無い要素は同じ順位（1）として読むので、rank の無い問いは組を持たない
    def order_pairs
      @question.expected.combination(2).filter_map do |a, b|
        rank_a = a[:rank] || 1
        rank_b = b[:rank] || 1
        next if rank_a == rank_b

        rank_a < rank_b ? [ a, b ] : [ b, a ]
      end
    end

    # 上位が結果の列（top-k で切らない）に出ていて、下位より先（下位が出ないときも守られた）
    def kept?(higher, lower)
      higher_at = position(higher)
      lower_at = position(lower)
      !higher_at.nil? && (lower_at.nil? || higher_at < lower_at)
    end

    def position(ref)
      @results.index { |card| matches?(card, ref) }
    end

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
