module Evaluation
  # 問いの集合を実行して採点する（docs/design/s1-eval-v2-plan.md 2.4）。
  # 採点の母数は status: active のみ。draft（人間レビュー前）と pending（正解不在の保留問）は一覧に残す。
  class Runner
    CardResult = Struct.new(:question, :results, :score, keyword_init: true)

    class Run
      attr_reader :card_results, :drafts, :pendings

      def initialize(card_results:, drafts:, pendings:)
        @card_results = card_results
        @drafts = drafts
        @pendings = pendings
      end

      def card_summary
        scores = card_results.map(&:score)
        total = scores.size
        {
          questions: total,
          hit_at_1: scores.count(&:hit_at_1),
          hit_at_3: scores.count(&:hit_at_3),
          complete_failures: scores.count(&:complete_failure),
          mrr: total.zero? ? 0.0 : scores.sum(&:reciprocal_rank) / total,
          recall_at_3: total.zero? ? 0.0 : scores.sum(&:recall_at_3) / total,
          violations: scores.count { |score| score.violations.any? },
          by_intent: by_intent
        }
      end

      private

      # intent_tag 別の hit（top-3 以内）の数／問題数。v1 と同じ軸（docs/reports/wp4-log.md R3）
      def by_intent
        card_results.group_by { |result| result.question.intent_tag }.transform_values do |group|
          { hits: group.count { |result| result.score.hit_at_3 }, total: group.size }
        end
      end
    end

    def self.run(questions)
      new(questions).run
    end

    def initialize(questions)
      @questions = questions
    end

    def run
      active = @questions.select(&:active?)
      Run.new(
        card_results: active.select(&:card?).map { |question| score_card(question) },
        drafts: @questions.select(&:draft?),
        pendings: @questions.select(&:pending?)
      )
    end

    private

    def score_card(question)
      results = Opt::PathcardSearch.call(question.query)
      CardResult.new(question: question, results: results, score: CardScorer.score(question, results))
    end
  end
end
