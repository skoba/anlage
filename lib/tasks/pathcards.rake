namespace :pathcards do
  desc "Extract pathcards for templates that do not have them"
  task backfill: :environment do
    Template.where(pathcards: nil).find_each do |template|
      cards = Opt::PathcardExtractor.call(template).cards
      template.update!(pathcards: cards)
    end
  end

  desc "Evaluate pathcard search against the WP4 seed questions"
  task eval: :environment do
    entries = YAML.load_file(Rails.root.join("spec/fixtures/pathcards_eval_seed.yml"))
    evaluations = entries.map do |entry|
      results = Opt::PathcardSearch.call(entry.fetch("query"))
      rank = results.index do |result|
        result.dig("identity", "archetype_id") == entry.fetch("expected_archetype_id")
      end

      entry.merge("rank" => rank, "hit" => !rank.nil?)
    end

    total = evaluations.size
    top1_count = evaluations.count { |evaluation| evaluation["rank"] == 0 }
    top3_count = evaluations.count do |evaluation|
      evaluation["rank"] && evaluation["rank"] < 3
    end
    failure_count = evaluations.count { |evaluation| !evaluation["hit"] }
    mrr = evaluations.sum do |evaluation|
      evaluation["rank"] ? 1.0 / (evaluation["rank"] + 1) : 0.0
    end / total
    intent_breakdown = evaluations.group_by { |evaluation| evaluation.fetch("intent_tag") }
                                  .transform_values do |group|
      { hits: group.count { |evaluation| evaluation["hit"] }, total: group.size }
    end

    percentage = ->(count) { format("%.2f%%", 100.0 * count / total) }

    puts "Pathcard search evaluation (phase1-bigram)"
    puts "Questions: #{total}"
    puts "Top-1 accuracy: #{top1_count}/#{total} (#{percentage.call(top1_count)})"
    puts "Top-3 accuracy: #{top3_count}/#{total} (#{percentage.call(top3_count)})"
    puts "Complete failure rate: #{failure_count}/#{total} (#{percentage.call(failure_count)})"
    puts "MRR: #{format('%.4f', mrr)}"
    puts "Intent breakdown (hits/questions):"
    intent_breakdown.each do |intent_tag, counts|
      puts "  #{intent_tag}: #{counts.fetch(:hits)}/#{counts.fetch(:total)}"
    end
    puts "Complete failures:"
    evaluations.reject { |evaluation| evaluation["hit"] }.each do |evaluation|
      puts "  #{evaluation.fetch('id')}: #{evaluation.fetch('query')}"
    end

    report_path = Rails.root.join("docs/reports/wp4-eval-log.md")
    unless report_path.exist?
      report_path.write(<<~HEADER)
        # WP4 パスカード検索評価ログ

        `pathcards:eval` の実行結果を時系列で記録し、検索実装の変更前後を比較する。

      HEADER
    end

    File.open(report_path, "a") do |report|
      report.puts "## #{Time.current.iso8601}"
      report.puts
      report.puts "- 検索実装: `phase1-bigram`"
      report.puts "- Top-1精度: #{top1_count}/#{total} (#{percentage.call(top1_count)})"
      report.puts "- Top-3精度: #{top3_count}/#{total} (#{percentage.call(top3_count)})"
      report.puts "- 完全失敗率: #{failure_count}/#{total} (#{percentage.call(failure_count)})"
      report.puts "- MRR: #{format('%.4f', mrr)}"
      report.puts "- intent_tag別内訳（hit数/問題数）:"
      intent_breakdown.each do |intent_tag, counts|
        report.puts "  - #{intent_tag}: #{counts.fetch(:hits)}/#{counts.fetch(:total)}"
      end
      report.puts
    end
  end
end
