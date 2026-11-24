# 評価 v2（docs/design/s1-eval-v2-plan.md、R-20261124-11）。v1 の `pathcards:eval` は残す（判断 D5）。
namespace :evaluation do
  desc "Run evaluation v2 (v1 seed via adapter, then the v2 gold in spec/fixtures/evaluation/v2). Prints Markdown; RESET=1 also scores aql questions (rebuilds the demo dataset)"
  task run: :environment do
    # v1 の 17 問は単独の表で出す（v1 の採点結果が変わらないことを保つ。R-20261124-15）
    puts Evaluation::Report.render(Evaluation::Runner.run(Evaluation::Questions.from_v1_seed), label: "phase1-bigram")

    gold = Evaluation::Questions.from_v2
    unless ENV["RESET"] == "1"
      skipped = gold.count(&:aql?)
      gold = gold.reject(&:aql?)
      puts "（aql の問いは RESET=1 のときだけ採点する。dataset を作り直して dev DB の記録を入れ替えるため。#{skipped} 問を飛ばした）"
      puts
    end
    puts Evaluation::Report.render(Evaluation::Runner.run(gold), label: "phase1-bigram、ゴールド v2")

    # 情報: v1 の問いを at_code まで見て集計する（docs/design/s1-eval-v2-plan.md 2.2。pin ではない）
    puts Evaluation::Report.render(Evaluation::Runner.run(Evaluation::Questions.from_v1_seed(match: :card)),
                                   label: "phase1-bigram、match: card")
  end
end
