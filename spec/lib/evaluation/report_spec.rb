require "rails_helper"

# Markdown 報告（docs/design/s1-eval-v2-plan.md 2.5、判断 D4）。ファイルには書かず、文字列を返す。
RSpec.describe Evaluation::Report do
  BP_V2 = "openEHR-EHR-OBSERVATION.blood_pressure.v2"
  PD_V1 = "openEHR-EHR-EVALUATION.problem_diagnosis.v1"

  def card_question(id, query, intent_tag:, **options)
    Evaluation::Question.new(id: id, kind: :card, query: query, intent_tag: intent_tag,
                             expected: [ { archetype_id: BP_V2, at_code: "at0004" } ], **options)
  end

  def card_result(question, rank:, violations: [])
    score = Evaluation::CardScorer::Score.new(rank: rank, hit_at_1: rank == 0, hit_at_3: !rank.nil? && rank < 3,
                                              recall_at_3: rank.nil? ? 0.0 : 1.0, reciprocal_rank: rank ? 1.0 / (rank + 1) : 0.0,
                                              complete_failure: rank.nil?, violations: violations)
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

  it "期待先がコーパスに現れた保留問は「保留解除候補」と印が付く" do
    releasable = Evaluation::Runner::Run.new(
      card_results: [], aql_results: [], drafts: [],
      pendings: [ card_question("c21", "既往歴", intent_tag: nil, status: :pending, pending_until: "story がコーパスに入る") ],
      corpus_archetype_ids: [ BP_V2 ]
    )
    expect(described_class.render(releasable, label: "x")).to include("- c21: 既往歴 — story がコーパスに入る **保留解除候補**")
  end
end
