module QueryBuilder
  # リンタの指摘 1 件（docs/design/s2-query-builder-plan.md 2.1）。
  #   severity: :error（実行しない）／:warning（実行はできるが結果が意図と違いうる）／:info（検査できなかった）
  #   code:     検査の名（:syntax, :variable, :path, :hop, :type, :value_set, :name_predicate, :unsupported）
  #   path:     問題の AQL 片（変数やパスの文字列。無いときは nil）
  Finding = Struct.new(:severity, :code, :message, :path, keyword_init: true) do
    def error? = severity == :error
  end
end
