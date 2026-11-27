module Evaluation
  module Grounding
    # 検索だけで、問いに必要なカードが候補に入る割合（R-20261127-25 の 3）。LLM を呼ばない。
    # 問いの文の全体をパスカード検索（Opt::PathcardSearch）にかけ、問いが指すカード（アーキタイプと at-code）が、すべて結果に入っているかを見る。
    # 測定の「接地あり」の腕は、検索で絞らず、索引のカードをすべて渡している。その理由と、検索の強化（S3）の材料になる数字。
    module SearchCoverage
      module_function

      def call(queries)
        queries.map do |query|
          hits = Opt::PathcardSearch.call(query.nl_query).map { |card| card.fetch("identity").values_at("archetype_id", "at_code") }
          missing = query.cards.map { |card| card.values_at(:archetype_id, :at_code) } - hits
          { id: query.id, style: query.style, hits: hits.size, covered: missing.empty?, missing: missing }
        end
      end

      def render(queries)
        rows = call(queries)
        lines = rows.group_by { |row| row[:style] }.sort.map { |style, group| line(style, group) } + [ line("計", rows) ]
        missed = rows.reject { |row| row[:covered] }.map { |row| "#{row[:id]}（検索の結果 #{row[:hits]} 枚。入らない: #{row[:missing].map(&:last).join('、')}）" }
        <<~MD
          ## 検索だけで、必要なカードが候補に入る割合

          問いの文の全体を、パスカード検索にかけた。LLM は呼んでいない。

          | 種類 | 問い | 必要なカードが、すべて検索の結果に入った |
          |---|---|---|
          #{lines.join("\n")}

          入らなかった問い: #{missed.empty? ? '無い' : missed.join('、')}
        MD
      end

      def line(name, rows)
        "| #{name} | #{rows.size} | #{rows.count { |row| row[:covered] }}/#{rows.size} |"
      end
    end
  end
end
