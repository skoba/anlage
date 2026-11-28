module Evaluation
  module Grounding
    # 試行（1 つの問い・1 つの腕・1 回の応答）の採点（docs/design/s4-nl-aql-plan.md 5.3 節・12 節。R-20261127-32）。
    #   status: :match（行の一致。列の順を見る。主の指標）／:overlooked（見落とし。血圧の片方の版だけの行と一致）／:mismatch／
    #           :lint（リンタかクエリビルダーで落ちた。実行しない）／:unexecutable／:unparseable（決まった形として読めない）
    #   order_free: 列の順を見ない一致（副の指標。行ごとに、値の多重集合として比べる。行の順も見ない）
    # 行は、順序を見ない多重集合として比べる。どの腕も、リンタの error がある AQL は実行しない。
    class Scorer
      Result = Struct.new(:status, :order_free, :parseable, :lint_ok, :executed, :card_match, :aqls, :rows, :reason, keyword_init: true)

      def self.score(query, arm:, response:, corpus: QueryBuilder::Corpus.active)
        new(query, arm, response, corpus).score
      end

      def initialize(query, arm, response, corpus)
        @query = query
        @arm = arm
        @response = response.to_s
        @corpus = corpus
      end

      def score
        @arm == :g_selection ? score_selection : score_aqls
      end

      private

      # --- AQL を書かせる腕

      def score_aqls
        aqls = parse_aqls
        return fail_with(:unparseable, "AQL として読めない応答", parseable: false) if aqls.empty?

        errors = aqls.flat_map { |aql| QueryBuilder::Linter.lint(aql, corpus: @corpus).findings.select(&:error?) }
        return fail_with(:lint, errors.map(&:message).join("／"), aqls: aqls) if errors.any?

        rows = aqls.flat_map { |aql| OpenehrRails::Aql::Executor.execute(aql).rows }
        compare(rows, aqls: aqls)
      rescue OpenehrRails::Aql::Error => e
        fail_with(:unexecutable, "#{e.class.name.demodulize}: #{e.message}", aqls: aqls, lint_ok: true)
      end

      # {"aqls": [...]}、AQL の文字の配列、AQL の文字だけ、のどれか
      def parse_aqls
        text = @response.strip
        data = [ text[/\{.*\}/m], text[/\[.*\]/m] ].compact.filter_map { |body| JSON.parse(body) rescue nil }.first
        list = data.is_a?(Hash) ? data["aqls"] : data
        list = [ text ] if list.nil? && text.match?(/\ASELECT\b/i)
        Array(list).select { |aql| aql.is_a?(String) && aql.match?(/\A\s*SELECT\b/i) }
      end

      # --- 選択を出す腕

      def score_selection
        candidates = NlQuery::Candidates.call(@query.nl_query, corpus: @corpus)
        parsed = NlQuery::SelectionParser.parse(@response, cards: candidates)
        return fail_with(:unparseable, parsed.reason, parseable: false) unless parsed.ok?

        selection = parsed.selection
        run = QueryBuilder::Runner.call(columns: selection[:columns], conditions: selection[:conditions], template_id: selection[:template_id],
                                        across_versions: selection[:across_versions], order: selection[:order], corpus: @corpus)
        card_match = card_match?(selection)
        return fail_with(:lint, run.error, card_match: card_match) if run.queries.empty?
        return fail_with(:lint, run.lint.findings.select(&:error?).map(&:message).join("／"), aqls: run.queries.map(&:aql), card_match: card_match) unless run.lint.ok?
        return fail_with(:unexecutable, run.error, aqls: run.queries.map(&:aql), lint_ok: true, card_match: card_match) unless run.executed?

        # 版の列（アーキタイプの ID）は、落として比べる。もとから版をまたぐ問い（a014 の文）は、落とさない
        rows = selection[:across_versions] && !@query.selection_only? ? run.rows.map { |row| row.drop(1) } : run.rows
        compare(rows, aqls: run.queries.map(&:aql), card_match: card_match)
      end

      # 選んだカード（アーキタイプと at-code。版の番号は見ない）が、問いの指すカードと同じか
      def card_match?(selection)
        chosen = selection[:columns] + selection[:conditions].flat_map { |condition| condition.key?(:any) ? condition[:any].map { |member| member[:card] } : [ condition[:card] ] }
        key = ->(archetype_id, at_code) { [ archetype_id.to_s.sub(/\.v\d+\z/, ""), at_code ] }
        chosen.map { |card| key.call(*card.fetch("identity").values_at("archetype_id", "at_code")) }.uniq.sort ==
          @query.cards.map { |card| key.call(card[:archetype_id], card[:at_code]) }.uniq.sort
      end

      # --- 比べる

      def compare(rows, aqls:, card_match: nil)
        actual = rows.map { |row| normalize(row) }
        expected = @query.expected_rows.map { |row| normalize(row) }
        status = if same?(actual, expected) then :match
        elsif overlooked?(actual) then :overlooked
        else :mismatch
        end
        # 行の順を見る問い（n013-2。R-20261128-3）: 行が合っていても、決めた列の順に並んでいなければ不正解
        unsorted = status == :match && @query.sorted_column && !sorted?(actual.map { |row| row[@query.sorted_column] })
        Result.new(status: unsorted ? :mismatch : status, order_free: same?(unordered(actual), unordered(expected)), parseable: true, lint_ok: true,
                   executed: true, card_match: card_match, aqls: aqls, rows: actual,
                   reason: ("行は合っているが、#{@query.sorted_column + 1} つめの列の順に並んでいない" if unsorted))
      end

      def overlooked?(actual)
        return false unless @query.overlook_measurable?

        @query.partial_rows.values.any? { |rows| same?(actual, rows.map { |row| normalize(row) }) }
      end

      # 昇順か降順のどちらかに並んでいるか。同じ値どうしの順は問わない。値の無い行は見ない
      def sorted?(values)
        present = values.compact
        present == present.sort || present == present.sort.reverse
      end

      def same?(left, right) = left.tally == right.tally
      def unordered(rows) = rows.map { |row| row.sort_by(&:inspect) }

      def normalize(row)
        row.map do |value|
          case value
          when Numeric then value.to_f
          when nil, true, false, String then value
          else value.to_s
          end
        end
      end

      def fail_with(status, reason, parseable: true, lint_ok: false, aqls: [], card_match: nil)
        Result.new(status: status, order_free: false, parseable: parseable, lint_ok: lint_ok, executed: false, card_match: card_match,
                   aqls: aqls, rows: [], reason: reason)
      end
    end
  end
end
