require "json"

module Evaluation
  module Grounding
    # 測定の記録（Run が残した <dir>/trials/*.json と run.json）から、集計を Markdown で作る。アダプタは呼ばない
    # （docs/design/s4-nl-aql-plan.md 5.3・5.4 節、12 節）。数字と限界を分けて書く。
    class Report
      STATUSES = %w[match overlooked mismatch lint unexecutable unparseable failed].freeze
      HEADERS = %w[正解 見落とし 不正解 リンタで落ちた 実行できない 読めない 呼び出しの失敗].freeze

      def self.render(dir, queries: Queries.load)
        new(dir, queries).render
      end

      def initialize(dir, queries)
        @dir = Pathname(dir)
        @meta = JSON.parse(@dir.join("run.json").read)
        @trials = @dir.glob("trials/*.json").sort.map { |path| JSON.parse(path.read) }
        @queries = queries.index_by(&:id)
      end

      def render
        [ heading, totals("すべての試行", @trials), totals("主の数字（値の言い換えの文を除く）", main_trials), stability, per_query, limits ].join("\n")
      end

      private

      def arms = @meta.fetch("arms")
      def main_trials = @trials.reject { |trial| @queries[trial["query"]]&.value_paraphrase? }

      def heading
        <<~MD
          # 測定の集計

          - アダプタ: #{@meta['adapter']}#{"（#{@meta['model']}）" if @meta['model']}。応答に入っていたモデルの名前: #{@trials.filter_map { |trial| trial['model'] }.uniq.join('、').presence || '—'}
          - 腕: #{arms.join('、')}。くり返し: #{@meta['repeats']} 回。試行: #{@trials.size}。索引のカード: #{@meta['cards']} 枚
          - 問いのファイルの sha256: #{@meta['queries_sha256']}。commit: #{@meta['commit']}。始めた時刻: #{@meta['started_at']}
          - 出力の形（JSON スキーマ）を渡した腕: #{@meta.fetch('json_schema', {}).select { |_, given| given }.keys.join('、').presence || '無い'}
        MD
      end

      # 主の指標は「正解」（行の一致。列の順を見る）。副の指標は「列の順を見ない一致」
      def totals(title, trials)
        rows = arms.map do |arm|
          mine = trials.select { |trial| trial["arm"] == arm }
          counts = STATUSES.map { |status| mine.count { |trial| trial["status"] == status } }
          "| #{arm} | #{mine.size} | #{counts.join(' | ')} | #{mine.count { |trial| trial['order_free'] }} |"
        end
        "## #{title}\n\n| 腕 | 試行 | #{HEADERS.join(' | ')} | 列の順を見ない一致 |\n|#{'---|' * (HEADERS.size + 3)}\n#{rows.join("\n")}\n"
      end

      # 問いごとの「何回のうち何回」から: いつも正解、いつも不正解、ゆれた、の問いの数。回ごとの正答率の最小と最大（5.4 節）
      def stability
        rows = arms.map do |arm|
          by_query = main_trials.select { |trial| trial["arm"] == arm }.group_by { |trial| trial["query"] }
          hits = by_query.transform_values { |trials| trials.count { |trial| trial["status"] == "match" } }
          always = by_query.count { |id, trials| hits[id] == trials.size }
          never = hits.count { |_, count| count.zero? }
          per_repeat = main_trials.select { |trial| trial["arm"] == arm }.group_by { |trial| trial["repeat"] }
                                  .map { |_, trials| trials.count { |trial| trial["status"] == "match" }.fdiv(trials.size) }
          range = per_repeat.empty? ? "—" : "#{(per_repeat.min * 100).round}〜#{(per_repeat.max * 100).round} %"
          "| #{arm} | #{by_query.size} | #{always} | #{never} | #{by_query.size - always - never} | #{range} |"
        end
        "## 問いごとのゆれ（主の数字の範囲で）\n\n| 腕 | 問い | いつも正解 | いつも不正解 | ゆれた | 回ごとの正答率の最小〜最大 |\n|---|---|---|---|---|---|\n#{rows.join("\n")}\n"
      end

      def per_query
        rows = @trials.group_by { |trial| [ trial["query"], trial["arm"] ] }.sort.map do |(id, arm), trials|
          query = @queries[id]
          tags = [ query&.style, *Array(query&.tags), ("見落としを見分けられない" if query&.both_versions? && !query.overlook_measurable?) ].compact.join("、")
          "| #{id} | #{arm} | #{trials.count { |trial| trial['status'] == 'match' }}/#{trials.size} | #{trials.count { |trial| trial['status'] == 'overlooked' }}/#{trials.size} | " \
            "#{trials.count { |trial| trial['order_free'] }}/#{trials.size} | #{tags} |"
        end
        "## 問いごと\n\n| 問い | 腕 | 正解 | 見落とし | 列の順を見ない一致 | 種類と印 |\n|---|---|---|---|---|---|\n#{rows.join("\n")}\n"
      end

      def limits
        <<~MD
          ## 限界

          - 問いは #{@trials.map { |trial| trial['query'] }.uniq.size} 文。数ポイントの差は言えない。大きな差だけを結果として読む
          - 問いは、このアプリのカードから作った。別のテンプレートや、別の診療科の語で、同じ成績になるとは言えない
          - 「接地あり」の腕は、索引のカードをすべて渡している（#{@meta['cards']} 枚）。検索で絞った候補ではない。索引が大きいときに同じ成績になるとは言えない
          - 見落とし（血圧の片方の版だけを引いた答え）は、正解にも不正解にも数えていない。片方の版に当たる記録が無い問い（a009 の文）は、見落としを見分けられない
          - モデルの出どころは、この記録では 1 つ（#{@meta['adapter']}）。同じ ID のモデルでも、日が変われば中身が変わりうる
        MD
      end
    end
  end
end
