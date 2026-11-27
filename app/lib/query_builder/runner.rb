module QueryBuilder
  # 組む → リンタ → 実行（docs/design/s2-query-builder-plan.md 6.3）。リンタの error があれば実行しない。
  # 組めない選択（Builder::InvalidSelection）と実行時の誤り（OpenehrRails::Aql::Error）は例外にせず、error に持つ。
  #
  # across_versions: 版をまたいで引く（docs/design/s2-cross-version-plan.md 4 節）。対応のある版ごとに AQL を組んで実行し、
  # 行をつなぐ。行の先頭に、その行が来たアーキタイプの ID（版つき）を足す。どれかの AQL にリンタの error があれば、どれも実行しない
  #
  # order: 並べ替え { card:, direction: }（Builder と同じ。skoba/anlage#242）。版をまたいで引くときは使えない
  class Runner
    # 版ごとの 1 本（版をまたがないときは 1 本だけで、archetype_id は nil）
    Query = Struct.new(:archetype_id, :aql, :lint, keyword_init: true)

    Run = Struct.new(:queries, :lint, :columns, :rows, :error, :executed, :version_column, keyword_init: true) do
      def executed? = executed
      def version_column? = version_column

      # 組んだ AQL（版をまたぐときは、版ごとの AQL を空行でつないだもの）。組めなかったときは nil
      def aql = queries.empty? ? nil : queries.map(&:aql).join("\n\n")
    end

    def self.call(columns:, conditions: [], template_id: false, execute: true, across_versions: false,
                  mappings: VersionMappings.default, corpus: nil, order: nil)
      new(columns, conditions, template_id, execute, across_versions, mappings, corpus, order).call
    end

    def initialize(columns, conditions, template_id, execute, across_versions, mappings, corpus, order = nil)
      @order = order
      @columns = columns
      @conditions = conditions
      @template_id = template_id
      @execute = execute
      @across_versions = across_versions
      @mappings = mappings
      @corpus = corpus
    end

    def call
      # 版ごとの AQL の行をつなぐので、並べ替えても全体の順にならない（skoba/anlage#242）
      raise Builder::InvalidSelection, "版をまたいで引くときは、並べ替えは使えない" if @order && @across_versions

      queries = selections.map do |selection|
        aql = Builder.build(columns: selection.columns, conditions: selection.conditions, template_id: @template_id, order: @order)
        Query.new(archetype_id: selection.archetype_id, aql: aql, lint: Linter.lint(aql))
      end
      lint = Linter::Lint.new(queries.flat_map { |query| query.lint.findings })
      return run(queries, lint) unless @execute && lint.ok?

      results = queries.map { |query| [ query, OpenehrRails::Aql::Executor.execute(query.aql) ] }
      rows = results.flat_map { |query, result| result.rows.map { |row| @across_versions ? [ query.archetype_id, *row ] : row } }
      run(queries, lint, columns: results.first&.last&.columns || [], rows: rows, executed: true)
    rescue Builder::InvalidSelection => e
      Run.new(queries: [], lint: nil, columns: [], rows: [], error: e.message, executed: false, version_column: @across_versions)
    rescue OpenehrRails::Aql::Error => e
      run(queries, lint, error: "#{e.class.name.demodulize}: #{e.message}")
    end

    private

    def selections
      unless @across_versions
        return [ CrossVersion::Selection.new(archetype_id: nil, columns: @columns, conditions: @conditions) ]
      end

      CrossVersion.selections(columns: @columns, conditions: @conditions, mappings: @mappings, corpus: @corpus || Corpus.active)
    end

    def run(queries, lint, columns: [], rows: [], error: nil, executed: false)
      Run.new(queries: queries, lint: lint, columns: columns, rows: rows, error: error, executed: executed, version_column: @across_versions)
    end
  end
end
