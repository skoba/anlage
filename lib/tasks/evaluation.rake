# 評価 v2（docs/design/s1-eval-v2-plan.md、R-20261124-11）。v1 の `pathcards:eval` は残す（判断 D5）。
namespace :evaluation do
  desc "Run evaluation v2 (v1 seed via adapter, then the v2 gold in spec/fixtures/evaluation/v2). Prints Markdown; RESET=1 also scores aql questions (rebuilds the demo dataset)"
  task run: :environment do
    # v1 の 17 問は単独の表で出す（v1 の採点結果が変わらないことを保つ。R-20261124-15）
    # ALIASES=0 で別名表を使わない（字面だけ。別名表の before を取る。docs/design/s3-search-plan.md 3.1）
    aliases = ENV["ALIASES"] == "0" ? Opt::SearchAliases.none : Opt::SearchAliases.default
    puts "（別名表を使わない）\n\n" if ENV["ALIASES"] == "0"
    puts Evaluation::Report.render(Evaluation::Runner.run(Evaluation::Questions.from_v1_seed, aliases: aliases), label: "phase1-bigram")

    gold = Evaluation::Questions.from_v2
    unless ENV["RESET"] == "1"
      skipped = gold.count(&:aql?)
      gold = gold.reject(&:aql?)
      puts "（aql の問いは RESET=1 のときだけ採点する。dataset を作り直して dev DB の記録を入れ替えるため。#{skipped} 問を飛ばした）"
      puts
    end
    puts Evaluation::Report.render(Evaluation::Runner.run(gold, aliases: aliases), label: "phase1-bigram、ゴールド v2")

    # 情報: v1 の問いを at_code まで見て集計する（docs/design/s1-eval-v2-plan.md 2.2。pin ではない）
    puts Evaluation::Report.render(Evaluation::Runner.run(Evaluation::Questions.from_v1_seed(match: :card), aliases: aliases),
                                   label: "phase1-bigram、match: card")
  end
end

# 接地あり・なしの測定（docs/design/s4-nl-aql-plan.md 5 節・7 節の段 6。R-20261127-32）。
#   NAME=<名前>           記録の置き場所 docs/reports/s4-runs/<名前>/（要る）
#   ADAPTER=<アダプタ>    recorded（既定）／local／lmstudio／anthropic／openai。外を呼ぶアダプタは EXTERNAL=1 を付けたときだけ
#   ARMS=n0,n1,g_aql,g_selection（既定は g_selection）  REPEATS=5  QUERIES=n001-1,n002-1（既定はすべて）
#   SEED=<数> TEMPERATURE=<数>   local と lmstudio のときだけ（乱数の種を固定した 1 回、など）
#   RESET=1               記録を demo:reset の初期状態に作り直してから回す（開発用の DB の記録を入れ替える）
# 済んだ試行は飛ばすので、途中で止めても、同じ NAME で続きから回せる。鍵は、環境変数から、アダプタが読む。記録には入らない
namespace :evaluation do
  desc "Run the grounded/ungrounded NL-to-AQL measurement (NAME=..., ADAPTER=recorded|local|lmstudio|anthropic|openai, ARMS=..., REPEATS=5). Never calls an external API unless EXTERNAL=1"
  task grounding: :environment do
    name = ENV["NAME"].to_s
    abort "NAME=<名前> が要る（記録は docs/reports/s4-runs/<名前>/ に残る）" unless name.match?(/\A[\w.-]+\z/)

    adapter_name = ENV.fetch("ADAPTER", "recorded")
    # 手元のモデルのアダプタ（同じ機械の中だけ）。温度と乱数の種を足せる
    on_this_machine = { "local" => Llm::Adapters::Local, "lmstudio" => Llm::Adapters::LmStudio }[adapter_name]
    adapter = if on_this_machine
      built, reason = on_this_machine.build(ENV.to_h, { seed: ENV["SEED"]&.to_i, temperature: ENV["TEMPERATURE"]&.to_f }.compact)
      abort "#{adapter_name} のアダプタを作れない: #{reason}" unless built
      built
    else
      settings = Llm::Settings.from_env(ENV.to_h.merge("ANLAGE_LLM" => adapter_name))
      abort "アダプタ #{adapter_name} を使えない: #{settings.reason}" unless settings.on?
      settings.adapter
    end
    abort "#{adapter_name} は、外に文を送る。EXTERNAL=1 を付けたときだけ回す" if adapter.external? && ENV["EXTERNAL"] != "1"

    Evaluation::Datasets.build("demo_initial") if ENV["RESET"] == "1"
    queries = Evaluation::Grounding::Queries.load
    queries = queries.select { |query| ENV["QUERIES"].split(",").include?(query.id) } if ENV["QUERIES"].present?
    arms = ENV.fetch("ARMS", "g_selection").split(",").map(&:to_sym)
    dir = Rails.root.join("docs/reports/s4-runs", name)
    Evaluation::Grounding::Run.call(queries: queries, arms: arms, adapter: adapter, repeats: ENV.fetch("REPEATS", "5").to_i, dir: dir, note: ENV["NOTE"],
                                    progress: ->(trial) { puts "#{trial[:query]} #{trial[:arm]} #{trial[:repeat]} #{trial[:status]} #{trial[:seconds]}s" })
    report = Evaluation::Grounding::Report.render(dir)
    dir.join("report.md").write(report)
    puts report
  end

  desc "Print how often the card search alone finds the cards each measurement question needs (no LLM)"
  task search_coverage: :environment do
    Evaluation::Datasets.build("demo_initial") if ENV["RESET"] == "1"
    puts Evaluation::Grounding::SearchCoverage.render(Evaluation::Grounding::Queries.load)
  end
end
