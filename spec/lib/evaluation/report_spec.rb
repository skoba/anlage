require "rails_helper"

# Markdown 報告（docs/design/s1-eval-v2-plan.md 2.5、判断 D4）。ファイルには書かず、文字列を返す。
RSpec.describe Evaluation::Report do
  BP_V2 = "openEHR-EHR-OBSERVATION.blood_pressure.v2"
  PD_V1 = "openEHR-EHR-EVALUATION.problem_diagnosis.v1"

  def card_question(id, query, intent_tag:, **options)
    Evaluation::Question.new(id: id, kind: :card, query: query, intent_tag: intent_tag,
                             expected: [ { archetype_id: BP_V2, at_code: "at0004" } ], **options)
  end

  def card_result(question, rank:, violations: [], order: [ 0, 0 ], acceptables: [])
    pairs, kept = order
    score = Evaluation::CardScorer::Score.new(rank: rank, hit_at_1: rank == 0, hit_at_3: !rank.nil? && rank < 3,
                                              recall_at_3: rank.nil? ? 0.0 : 1.0, reciprocal_rank: rank ? 1.0 / (rank + 1) : 0.0,
                                              complete_failure: rank.nil?, violations: violations,
                                              order_pairs: pairs, order_pairs_kept: kept,
                                              order_kept: pairs.zero? ? nil : pairs == kept, acceptables: acceptables)
    Evaluation::Runner::CardResult.new(question: question, results: [], score: score)
  end

  let(:run) do
    hit = card_result(card_question("c01", "収縮期", intent_tag: "bigram成立想定"), rank: 0)
    second = card_result(card_question("c02", "臨床検査", intent_tag: "複合語"), rank: 1,
                         violations: [ { archetype_id: PD_V1, at_code: "at0003" } ])
    miss = card_result(card_question("c03", "BMI", intent_tag: "同義語ギャップ"), rank: nil)
    aql_ok = Evaluation::Runner::AqlResult.new(
      question: Evaluation::Question.new(id: "a01", kind: :aql, query: "収縮期血圧が 110 を超える記録", dataset: "demo_initial",
                                         reference_aql: "SELECT 1", expected_rows: [ [ 120.0 ] ]),
      score: Evaluation::AqlScorer::Score.new(status: :match, rows: [ [ 120.0 ] ], missing: [], extra: [])
    )
    aql_ng = Evaluation::Runner::AqlResult.new(
      question: Evaluation::Question.new(id: "a02", kind: :aql, query: "疑いの傷病名", dataset: "demo_initial",
                                         reference_aql: "SELECT 2", expected_rows: [ [ "疑い" ] ]),
      score: Evaluation::AqlScorer::Score.new(status: :mismatch, rows: [ [ "推定" ] ], missing: [ [ "疑い" ] ], extra: [ [ "推定" ] ])
    )
    Evaluation::Runner::Run.new(
      card_results: [ hit, second, miss ], aql_results: [ aql_ok, aql_ng ],
      drafts: [ card_question("c21", "既往歴", intent_tag: "同義語ギャップ", status: :draft) ],
      pendings: [ Evaluation::Question.new(id: "c19", kind: :card, status: :pending, query: "検体",
                                           expected: [ { archetype_id: "openEHR-EHR-CLUSTER.specimen.v1", at_code: nil } ],
                                           pending_until: "specimen を含む OPT がコーパスに入る") ],
      corpus_archetype_ids: [ BP_V2 ]
    )
  end

  subject(:markdown) { described_class.render(run, label: "phase1-bigram") }

  it "card の集計表（Top-1・Top-3・完全失敗・MRR・recall@3・負例違反）と intent_tag 別の内訳を出す" do
    expect(markdown).to include("# 評価 v2（phase1-bigram）", "## card（3 問）",
                                "| Top-1 | 1/3 (33.33%) |", "| Top-3 | 2/3 (66.67%) |", "| 完全失敗 | 1/3 (33.33%) |",
                                "| MRR | 0.5000 |", "| recall@3 | 0.6667 |", "| 負例違反 | 1/3 |",
                                "- bigram成立想定: 1/1", "- 複合語: 1/1", "- 同義語ギャップ: 0/1")
  end

  it "完全失敗と負例違反の一覧、aql の集計と不一致の差分、draft と保留問（解除候補つき）の一覧を出す" do
    expect(markdown).to include("### 完全失敗\n\n- c03: BMI",
                                "### 負例違反\n\n- c02: 臨床検査 → #{PD_V1} at0003",
                                "## aql（2 問）", "| 一致 | 1/2 |", "| 不一致 | 1/2 |", "| 実行不能 | 0/2 |",
                                "- a02: 疑いの傷病名 — 不足 [[\"疑い\"]] 余分 [[\"推定\"]]",
                                "## draft（1 問、母数外）\n\n- c21: 既往歴",
                                "## 保留問（1 問、母数外）\n\n- c19: 検体 — specimen を含む OPT がコーパスに入る")
    expect(markdown).not_to include("保留解除候補")
  end

  # 順位と許容（docs/design/s1-eval-v2-plan.md 7 節、R-20261124-15）
  it "順位の組を持つ問いが無ければ、順位遵守は 0/0、許容の出現は 0/3 で、一覧は（なし）" do
    expect(markdown).to include("| 順位遵守 | 0/0（組 0/0） |", "| 許容の出現 | 0/3 |",
                                "### 順位が守られなかった問い\n\n（なし）", "### 許容の出現\n\n（なし）")
  end

  it "順位遵守（問い単位と組の数）、守られなかった問い、許容が top-3 に出た問いを出す" do
    kept = card_result(card_question("c08", "発症", intent_tag: "bigram成立想定"), rank: 0, order: [ 1, 1 ])
    broken = card_result(card_question("c09", "診断", intent_tag: "bigram成立想定"), rank: 0, order: [ 2, 1 ])
    plain = card_result(card_question("c15", "臨床検査", intent_tag: "複合語"), rank: 0,
                        acceptables: [ { archetype_id: PD_V1, at_code: "at0002" } ])
    ranked_run = Evaluation::Runner::Run.new(card_results: [ kept, broken, plain ], aql_results: [], drafts: [], pendings: [],
                                             corpus_archetype_ids: [])

    expect(described_class.render(ranked_run, label: "x")).to include(
      "| 順位遵守 | 1/2 (50.00%)（組 2/3） |", "| 許容の出現 | 1/3 |",
      "### 順位が守られなかった問い\n\n- c09: 診断（組 1/2）",
      "### 許容の出現\n\n- c15: 臨床検査 → #{PD_V1} at0002"
    )
  end

  # S2 の経路（R-20261124-21 の作業列 3）
  it "S2 の経路の集計（一致・不一致・実行不能・組めない）と、一致しなかった問いの理由と AQL を出す。selection を持つ問いが無ければ節を出さない" do
    expect(markdown).not_to include("S2 の経路")

    question = Evaluation::Question.new(id: "a03", kind: :aql, query: "疑いの傷病名", dataset: "demo_initial", reference_aql: "SELECT 3",
                                        expected_rows: [ [ "疑い" ] ], selection: { columns: [], conditions: [] })
    reference = Evaluation::AqlScorer::Score.new(status: :match, rows: [], missing: [], extra: [])
    ok = Evaluation::Runner::AqlResult.new(question: question, score: reference,
                                           builder_score: Evaluation::BuilderRoute::Score.new(status: :match, aql: "SELECT ok", missing: [], extra: []))
    ng = Evaluation::Runner::AqlResult.new(question: question, score: reference,
                                           builder_score: Evaluation::BuilderRoute::Score.new(status: :unbuildable, aql: nil, missing: [], extra: [],
                                                                                              error: "索引にカードが無い: x at0001"))
    diff = Evaluation::Runner::AqlResult.new(question: question, score: reference,
                                             builder_score: Evaluation::BuilderRoute::Score.new(status: :mismatch, aql: "SELECT ng", missing: [ [ "疑い" ] ], extra: []))
    route_run = Evaluation::Runner::Run.new(card_results: [], aql_results: [ ok, ng, diff ], drafts: [], pendings: [], corpus_archetype_ids: [])

    expect(described_class.render(route_run, label: "x")).to include(
      "## aql: S2 の経路（クエリビルダーが組んだ AQL。3 問）", "| 一致 | 1/3 |", "| 不一致 | 1/3 |", "| 実行不能 | 0/3 |", "| 組めない | 1/3 |",
      "- a03: 疑いの傷病名 — 組めない: 索引にカードが無い: x at0001",
      "- a03: 疑いの傷病名 — 不一致: 不足 [[\"疑い\"]] 余分 []（SELECT ng）"
    )
  end

  it "期待先がコーパスに現れた保留問は「保留解除候補」と印が付く" do
    releasable = Evaluation::Runner::Run.new(
      card_results: [], aql_results: [], drafts: [],
      pendings: [ card_question("c21", "既往歴", intent_tag: nil, status: :pending, pending_until: "story がコーパスに入る") ],
      corpus_archetype_ids: [ BP_V2 ]
    )
    expect(described_class.render(releasable, label: "x")).to include("- c21: 既往歴 — story がコーパスに入る **保留解除候補**")
  end
  # 負例だけの問い（docs/design/s1-eval-v2-plan.md 9 節、R-20261125-7）
  it "負例だけの問いの節: 問いの数、負例が上位（top-3）に出た問いの数と、出た負例。card の集計表は変わらない" do
    bmi = { archetype_id: "openEHR-EHR-OBSERVATION.body_mass_index.v2", at_code: nil }
    clean = card_result(Evaluation::Question.new(id: "n1", kind: :card, query: "肥満度", expected: [], forbidden: [ bmi ]), rank: nil)
    violated = card_result(Evaluation::Question.new(id: "n2", kind: :card, query: "BMI判定", expected: [], forbidden: [ bmi ]), rank: nil,
                           violations: [ bmi ])
    with_negatives = Evaluation::Runner::Run.new(card_results: run.card_results, aql_results: [], drafts: [], pendings: [],
                                                 corpus_archetype_ids: [], negative_results: [ clean, violated ])
    markdown = described_class.render(with_negatives, label: "x")

    expect(markdown).to include("## card（3 問）", "| Top-1 | 1/3 (33.33%) |", "| 負例違反 | 1/3 |",
                                "## card: 負例だけの問い（2 問）", "| 負例が上位（top-3）に出た問い | 1/2 |",
                                "### 負例が上位に出た問い\n\n- n2: BMI判定 → openEHR-EHR-OBSERVATION.body_mass_index.v2")
    expect(markdown.index("## card: 負例だけの問い")).to be_between(markdown.index("## card（3 問）"), markdown.index("## aql"))
  end

  it "負例だけの問いが無ければ、節を出さない" do
    expect(markdown).not_to include("負例だけの問い")
  end
  # 別名表（docs/design/s3-search-plan.md 3.1、R-20261125-8）: 問いの語が表にある問いと、無い問いを分けて数える。
  # 表の行は評価の注記から作ったので、表にある語の問いが当たるのは当然で、効果の数字に入れない
  it "別名表にある語の問いと、無い語の問いの内訳（問いの数、Top-1、Top-3）を出す。表にある語の問いが無ければ節を出さない" do
    table = Opt::SearchAliases.new([ { "term" => "BMI", "relation" => "alias", "targets" => [ { "archetype_id" => BP_V2 } ],
                                       "source" => "spec", "reviewed_by" => "x", "reviewed_at" => Date.new(2026, 11, 25) } ])
    split_run = Evaluation::Runner::Run.new(card_results: run.card_results, aql_results: [], drafts: [], pendings: [],
                                            corpus_archetype_ids: [], aliases: table)

    expect(described_class.render(split_run, label: "x")).to include(
      "## card: 別名表にある語の問いと、無い語の問い",
      "| 別名表にある語（効果の数字に入れない） | 1 | 0/1 (0.00%) | 0/1 (0.00%) |",
      "| 別名表に無い語 | 2 | 1/2 (50.00%) | 2/2 (100.00%) |",
      "別名表にある語の問い: c03（BMI）"
    )
    expect(markdown).not_to include("別名表にある語")
  end
end
