module Evaluation
  # 問いの集合を実行して採点する（docs/design/s1-eval-v2-plan.md 2.4）。
  # 採点の母数は status: active のみ。draft（人間レビュー前）と pending（正解不在の保留問）は一覧に残す。
  class Runner
    CardResult = Struct.new(:question, :results, :score, keyword_init: true)
    # builder_score: S2 の経路（selection からビルダーが組んだ AQL）の採点。selection の無い問いは nil
    AqlResult = Struct.new(:question, :score, :builder_score, keyword_init: true)

    class Run
      attr_reader :card_results, :negative_results, :aql_results, :drafts, :pendings

      # negative_results: 負例だけの問い（docs/design/s1-eval-v2-plan.md 9 節）。card_results（期待を持つ問い）とは別に持つ
      # aliases: 検索が使った別名表。問いの語が表にあるかどうかで、集計を分けるのに使う（docs/design/s3-search-plan.md 3.1）
      def initialize(card_results:, aql_results:, drafts:, pendings:, corpus_archetype_ids:, negative_results: [],
                     aliases: Opt::SearchAliases.none)
        @aliases = aliases
        @card_results = card_results
        @negative_results = negative_results
        @aql_results = aql_results
        @drafts = drafts
        @pendings = pendings
        @corpus_archetype_ids = corpus_archetype_ids
      end

      def aql_summary
        statuses = aql_results.map { |result| result.score.status }
        { questions: statuses.size, match: statuses.count(:match), mismatch: statuses.count(:mismatch),
          unexecutable: statuses.count(:unexecutable) }
      end

      # S2 の経路（docs/design/s1-eval-v2-plan.md 8 節）。母数は selection を持つ aql の問い
      def builder_summary
        statuses = aql_results.filter_map { |result| result.builder_score&.status }
        { questions: statuses.size, match: statuses.count(:match), mismatch: statuses.count(:mismatch),
          unexecutable: statuses.count(:unexecutable), unbuildable: statuses.count(:unbuildable) }
      end

      # 問いの語が別名表にある問いと、無い問いの内訳。表の行は評価の注記から作ったので、表にある語の問いは効果の数字に入れない
      def alias_split
        in_table, out_of_table = card_results.partition { |result| @aliases.include?(result.question.query) }
        { in_table: split_counts(in_table), out_of_table: split_counts(out_of_table) }
      end

      # 負例だけの問いの数と、負例が上位（top-3）に出た問いの数。Top-1 などの集計（card_summary）には入れない
      def negative_summary
        { questions: negative_results.size, violations: negative_results.count { |result| result.score.violations.any? } }
      end

      # 保留問のうち、期待先のアーキタイプがすべてコーパス（active のテンプレートのカード）に現れたもの。
      # 一部だけ（c021 の problem_diagnosis のように、もとからコーパスにある正解）では解除候補にしない。
      # 出題化（status を active に戻す）の判断は人間に回す
      def releasable_pendings
        pendings.select do |question|
          question.expected.any? && question.expected.all? { |ref| @corpus_archetype_ids.include?(ref[:archetype_id]) }
        end
      end

      def card_summary
        scores = card_results.map(&:score)
        total = scores.size
        ranked = scores.select { |score| score.order_pairs.positive? }
        {
          questions: total,
          hit_at_1: scores.count(&:hit_at_1),
          hit_at_3: scores.count(&:hit_at_3),
          complete_failures: scores.count(&:complete_failure),
          mrr: total.zero? ? 0.0 : scores.sum(&:reciprocal_rank) / total,
          recall_at_3: total.zero? ? 0.0 : scores.sum(&:recall_at_3) / total,
          violations: scores.count { |score| score.violations.any? },
          # 順位（docs/design/s1-eval-v2-plan.md 7.2）: 順位の組を持つ問いだけが母数。rank の無い問いは入らない
          ranked_questions: ranked.size,
          order_kept: ranked.count(&:order_kept),
          order_pairs: ranked.sum(&:order_pairs),
          order_pairs_kept: ranked.sum(&:order_pairs_kept),
          acceptables: scores.count { |score| score.acceptables.any? },
          by_intent: by_intent
        }
      end

      private

      def split_counts(results)
        { questions: results.size, hit_at_1: results.count { |result| result.score.hit_at_1 },
          hit_at_3: results.count { |result| result.score.hit_at_3 }, ids: results.map { |result| result.question.id } }
      end

      # intent_tag 別の hit（top-3 以内）の数／問題数。v1 と同じ軸（docs/reports/wp4-log.md R3）
      def by_intent
        card_results.group_by { |result| result.question.intent_tag }.transform_values do |group|
          { hits: group.count { |result| result.score.hit_at_3 }, total: group.size }
        end
      end
    end

    # aliases: 検索に使う別名表。Opt::SearchAliases.none を渡すと字面だけで採点する（別名表を入れる前の数字）
    def self.run(questions, aliases: Opt::SearchAliases.default)
      new(questions, aliases).run
    end

    def initialize(questions, aliases = Opt::SearchAliases.default)
      @questions = questions
      @aliases = aliases
    end

    def run
      active = @questions.select(&:active?)
      negatives, cards = active.select(&:card?).partition(&:negative_only?)
      Run.new(
        card_results: cards.map { |question| score_card(question) },
        negative_results: negatives.map { |question| score_card(question) },
        aql_results: score_aql_by_dataset(active.select(&:aql?)),
        drafts: @questions.select(&:draft?),
        pendings: @questions.select(&:pending?),
        corpus_archetype_ids: corpus_archetype_ids,
        aliases: @aliases
      )
    end

    private

    def score_card(question)
      results = Opt::PathcardSearch.call(question.query, aliases: @aliases)
      CardResult.new(question: question, results: results, score: CardScorer.score(question, results))
    end

    # dataset ごとに 1 回だけ初期状態を作ってから採点する（dataset の作成はテンプレートも入れ替えるので、card の採点のあとに回す）
    def score_aql_by_dataset(questions)
      questions.group_by(&:dataset).flat_map do |dataset, group|
        Datasets.build(dataset)
        group.map do |question|
          AqlResult.new(question: question, score: AqlScorer.score(question), builder_score: BuilderRoute.score(question))
        end
      end
    end

    def corpus_archetype_ids
      Template.active.where.not(pathcards: nil).flat_map do |template|
        Array(template.pathcards).map { |card| card.dig("identity", "archetype_id") }
      end.uniq
    end
  end
end
