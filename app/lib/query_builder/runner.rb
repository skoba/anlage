module QueryBuilder
  # 組む → リンタ → 実行（docs/design/s2-query-builder-plan.md 6.3）。リンタの error があれば実行しない。
  # 組めない選択（Builder::InvalidSelection）と実行時の誤り（OpenehrRails::Aql::Error）は例外にせず、error に持つ。
  class Runner
    Run = Struct.new(:aql, :lint, :columns, :rows, :error, :executed, keyword_init: true) do
      def executed? = executed
    end

    def self.call(columns:, conditions: [], composition_name: false, execute: true)
      aql = Builder.build(columns: columns, conditions: conditions, composition_name: composition_name)
      lint = Linter.lint(aql)
      return Run.new(aql: aql, lint: lint, columns: [], rows: [], executed: false) unless execute && lint.ok?

      result = OpenehrRails::Aql::Executor.execute(aql)
      Run.new(aql: aql, lint: lint, columns: result.columns, rows: result.rows, executed: true)
    rescue Builder::InvalidSelection => e
      Run.new(aql: nil, lint: nil, columns: [], rows: [], error: e.message, executed: false)
    rescue OpenehrRails::Aql::Error => e
      Run.new(aql: aql, lint: lint, columns: [], rows: [], error: "#{e.class.name.demodulize}: #{e.message}", executed: false)
    end
  end
end
