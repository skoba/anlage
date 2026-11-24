module Evaluation
  # aql の問いの採点（docs/design/s1-eval-v2-plan.md 2.4、判断 D2）。採点対象は AQL 文字列で、既定は参照 AQL 自身
  # （ゴールドの健全性の pin）。S2（クエリビルダー）・S4（自然言語→AQL）は同じ採点器に別の AQL を渡す。
  # 行は多重集合として比べる（ordered: true なら順序も）。実行できない AQL は例外で止めず unexecutable に数える。
  class AqlScorer
    Score = Struct.new(:status, :rows, :missing, :extra, :error, keyword_init: true)

    def self.score(question, aql: question.reference_aql)
      new(question, aql).score
    end

    def initialize(question, aql)
      @question = question
      @aql = aql
    end

    def score
      actual = OpenehrRails::Aql::Executor.execute(@aql).rows.map { |row| normalize(row) }
      expected = @question.expected_rows.map { |row| normalize(row) }
      missing, extra = @question.ordered ? ordered_diff(expected, actual) : multiset_diff(expected, actual)

      Score.new(status: missing.empty? && extra.empty? ? :match : :mismatch, rows: actual, missing: missing, extra: extra)
    rescue OpenehrRails::Aql::Error => e
      Score.new(status: :unexecutable, rows: [], missing: [], extra: [], error: "#{e.class.name.demodulize}: #{e.message}")
    end

    private

    # OpenEHR::AQL::ResultSet#to_json と同じ写像: 数値は Float、JSON の基本値はそのまま、RM オブジェクトは canonical JSON に落とす。
    def normalize(row)
      row.map do |value|
        case value
        when Numeric then value.to_f
        when nil, true, false, String then value
        else JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(value).serialize)
        end
      end
    end

    def multiset_diff(expected, actual)
      expected_tally = expected.tally
      actual_tally = actual.tally
      missing = expected_tally.flat_map { |row, n| [ row ] * [ n - actual_tally.fetch(row, 0), 0 ].max }
      extra = actual_tally.flat_map { |row, n| [ row ] * [ n - expected_tally.fetch(row, 0), 0 ].max }
      [ missing, extra ]
    end

    def ordered_diff(expected, actual)
      return [ [], [] ] if expected == actual

      multiset_diff(expected, actual).then { |missing, extra| missing.empty? && extra.empty? ? [ expected, actual ] : [ missing, extra ] }
    end
  end
end
