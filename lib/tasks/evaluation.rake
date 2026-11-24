# 評価 v2（docs/design/s1-eval-v2-plan.md、R-20261124-11）。v1 の `pathcards:eval` は残す（判断 D5）。
namespace :evaluation do
  desc "Run evaluation v2 (v1 seed via adapter + spec/fixtures/evaluation/v2). Prints Markdown; RESET=1 also scores aql questions (rebuilds the demo dataset)"
  task run: :environment do
    questions = Evaluation::Questions.from_v1_seed + Evaluation::Questions.from_v2
    unless ENV["RESET"] == "1"
      skipped = questions.count(&:aql?)
      questions = questions.reject(&:aql?)
      puts "（aql の問いは RESET=1 のときだけ採点する。dataset を作り直して dev DB の記録を入れ替えるため。#{skipped} 問を飛ばした）"
      puts
    end

    puts Evaluation::Report.render(Evaluation::Runner.run(questions), label: "phase1-bigram")
  end
end
