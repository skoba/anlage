module Evaluation
  # Markdown の報告（docs/design/s1-eval-v2-plan.md 2.5、判断 D4）。標準出力に出す文字列を返すだけで、ファイルには書かない
  # （v1 の自動追記は同一値の重複で雑音になった）。記録はセッションが docs/reports/ のログに貼る。
  module Report
    module_function

    def render(run, label:)
      [ "# 評価 v2（#{label}）", card_section(run), negative_section(run), aql_section(run), builder_section(run), draft_section(run), pending_section(run) ]
        .compact.join("\n\n") + "\n"
    end

    def card_section(run)
      summary = run.card_summary
      total = summary.fetch(:questions)
      lines = [ "## card（#{total} 問）", "" ]
      lines << "| 指標 | 値 |" << "|---|---|"
      lines << "| Top-1 | #{ratio(summary.fetch(:hit_at_1), total)} |"
      lines << "| Top-3 | #{ratio(summary.fetch(:hit_at_3), total)} |"
      lines << "| 完全失敗 | #{ratio(summary.fetch(:complete_failures), total)} |"
      lines << "| MRR | #{format('%.4f', summary.fetch(:mrr))} |"
      lines << "| recall@3 | #{format('%.4f', summary.fetch(:recall_at_3))} |"
      lines << "| 負例違反 | #{summary.fetch(:violations)}/#{total} |"
      lines << "| 順位遵守 | #{ratio(summary.fetch(:order_kept), summary.fetch(:ranked_questions))}" \
               "（組 #{summary.fetch(:order_pairs_kept)}/#{summary.fetch(:order_pairs)}） |"
      lines << "| 許容の出現 | #{summary.fetch(:acceptables)}/#{total} |"
      lines << "" << "intent_tag 別（hit@3／問題数）:" << ""
      summary.fetch(:by_intent).each { |tag, counts| lines << "- #{tag || '（タグ無し）'}: #{counts.fetch(:hits)}/#{counts.fetch(:total)}" }
      lines << "" << "### 完全失敗" << ""
      lines.concat(list(run.card_results.select { |result| result.score.complete_failure }) { |result| "#{result.question.id}: #{result.question.query}" })
      lines << "" << "### 負例違反" << ""
      lines.concat(list(run.card_results.select { |result| result.score.violations.any? }) do |result|
        "#{result.question.id}: #{result.question.query} → #{refs(result.score.violations)}"
      end)
      lines << "" << "### 順位が守られなかった問い" << ""
      lines.concat(list(run.card_results.select { |result| result.score.order_kept == false }) do |result|
        "#{result.question.id}: #{result.question.query}（組 #{result.score.order_pairs_kept}/#{result.score.order_pairs}）"
      end)
      lines << "" << "### 許容の出現" << ""
      lines.concat(list(run.card_results.select { |result| result.score.acceptables.any? }) do |result|
        "#{result.question.id}: #{result.question.query} → #{refs(result.score.acceptables)}"
      end)
      lines.join("\n")
    end

    # 負例だけの問い（期待が空で、負例だけを持つ。docs/design/s1-eval-v2-plan.md 9 節）。問いが無ければ節を出さない
    def negative_section(run)
      summary = run.negative_summary
      total = summary.fetch(:questions)
      return nil if total.zero?

      lines = [ "## card: 負例だけの問い（#{total} 問）", "", "| 指標 | 値 |", "|---|---|" ]
      lines << "| 負例が上位（top-3）に出た問い | #{summary.fetch(:violations)}/#{total} |"
      lines << "" << "### 負例が上位に出た問い" << ""
      lines.concat(list(run.negative_results.select { |result| result.score.violations.any? }) do |result|
        "#{result.question.id}: #{result.question.query} → #{refs(result.score.violations)}"
      end)
      lines.join("\n")
    end

    def aql_section(run)
      summary = run.aql_summary
      total = summary.fetch(:questions)
      lines = [ "## aql（#{total} 問）", "", "| 結果 | 数 |", "|---|---|" ]
      lines << "| 一致 | #{summary.fetch(:match)}/#{total} |"
      lines << "| 不一致 | #{summary.fetch(:mismatch)}/#{total} |"
      lines << "| 実行不能 | #{summary.fetch(:unexecutable)}/#{total} |"
      lines << "" << "### 不一致と実行不能" << ""
      lines.concat(list(run.aql_results.reject { |result| result.score.status == :match }) do |result|
        score = result.score
        detail = score.status == :unexecutable ? score.error : "不足 #{score.missing.to_json} 余分 #{score.extra.to_json}"
        "#{result.question.id}: #{result.question.query} — #{detail}"
      end)
      lines.join("\n")
    end

    # S2 の経路。selection を持つ問いが無ければ節を出さない
    def builder_section(run)
      summary = run.builder_summary
      total = summary.fetch(:questions)
      return nil if total.zero?

      names = { mismatch: "不一致", unexecutable: "実行不能", unbuildable: "組めない" }
      lines = [ "## aql: S2 の経路（クエリビルダーが組んだ AQL。#{total} 問）", "", "| 結果 | 数 |", "|---|---|" ]
      lines << "| 一致 | #{summary.fetch(:match)}/#{total} |"
      names.each { |status, name| lines << "| #{name} | #{summary.fetch(status)}/#{total} |" }
      lines << "" << "### 一致しなかった問い" << ""
      failed = run.aql_results.select { |result| result.builder_score && result.builder_score.status != :match }
      lines.concat(list(failed) do |result|
        score = result.builder_score
        detail = score.status == :mismatch ? "不足 #{score.missing.to_json} 余分 #{score.extra.to_json}（#{score.aql.to_s.squish}）" : score.error
        "#{result.question.id}: #{result.question.query} — #{names.fetch(score.status)}: #{detail}"
      end)
      lines.join("\n")
    end

    def draft_section(run)
      ([ "## draft（#{run.drafts.size} 問、母数外）", "" ] + list(run.drafts) { |question| "#{question.id}: #{question.query}" }).join("\n")
    end

    def pending_section(run)
      releasable = run.releasable_pendings
      items = list(run.pendings) do |question|
        mark = releasable.include?(question) ? " **保留解除候補**" : ""
        "#{question.id}: #{question.query} — #{question.pending_until}#{mark}"
      end
      ([ "## 保留問（#{run.pendings.size} 問、母数外）", "" ] + items).join("\n")
    end

    def refs(list)
      list.map { |ref| [ ref[:archetype_id], ref[:at_code] ].compact.join(" ") }.join("、")
    end

    def ratio(count, total)
      return "#{count}/#{total}" if total.zero?

      format("%d/%d (%.2f%%)", count, total, 100.0 * count / total)
    end

    def list(items)
      return [ "（なし）" ] if items.empty?

      items.map { |item| "- #{yield(item)}" }
    end
  end
end
