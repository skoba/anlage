require "rails_helper"

# aql の問いの採点（docs/design/s1-eval-v2-plan.md 2.3・2.4）。データセット demo_initial は rake demo:reset と同じ初期状態
# （fixture 5 件 ＋ Demo::SampleCompositions。CardiologyEncounter の血圧は 120/80、ProblemList は高血圧症と 2型糖尿病、
# jp_referral の骨格に 2型糖尿病）。パスは spec/fixtures/pathcards/CardiologyEncounter.golden.json の identity.path。
RSpec.describe Evaluation::AqlScorer do
  SYSTOLIC_OVER_110 = <<~AQL
    SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude AS systolic
    FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
    WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude > 110
  AQL

  CROSS_TEMPLATE_DIAGNOSES = <<~AQL
    SELECT c/name/value AS composition_name,
           ev/data[at0001]/items[at0002]/value/value AS diagnosis
    FROM EHR e CONTAINS COMPOSITION c
         CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
    WHERE ev/data[at0001]/items[at0002]/value/value MATCHES {"2型糖尿病", "高血圧症"}
  AQL

  before { Evaluation::Datasets.build("demo_initial") }

  def question(reference_aql, expected_rows, ordered: false)
    Evaluation::Question.new(id: "a", kind: :aql, query: "q", dataset: "demo_initial",
                             reference_aql: reference_aql, expected_rows: expected_rows, ordered: ordered)
  end

  it "参照 AQL の結果が期待行と一致すれば match（YAML の整数 120 と結果の 120.0 は同じ値）" do
    score = described_class.score(question(SYSTOLIC_OVER_110, [ [ 120 ] ]))

    expect(score).to have_attributes(status: :match, rows: [ [ 120.0 ] ], missing: [], extra: [])
  end

  it "期待行は多重集合として比べる（順序が違っても match）。ordered: true なら順序も見る" do
    expected = [ [ "jp_referral", "2型糖尿病" ], [ "ProblemList", "高血圧症" ], [ "ProblemList", "2型糖尿病" ] ]

    expect(described_class.score(question(CROSS_TEMPLATE_DIAGNOSES, expected)).status).to eq(:match)
    expect(described_class.score(question(CROSS_TEMPLATE_DIAGNOSES, expected, ordered: true)).status).to eq(:mismatch)
  end

  it "1 行違えば mismatch で、不足と余分の行が出る" do
    score = described_class.score(question(SYSTOLIC_OVER_110, [ [ 130.0 ] ]))

    expect(score).to have_attributes(status: :mismatch, missing: [ [ 130.0 ] ], extra: [ [ 120.0 ] ])
  end

  # openehr 2.5.0 で defining_code/code_string には届くようになった（上流候補 10 項は解消）。
  # openehr 2.6.0 で archetype_details も例外にならなくなった（値は nil。上流候補 25 項の追記）。届かない例は COMPOSITION の uid
  # （openehr-rails 0.10.0 CHANGELOG の Known limitations、rails #46）
  it "エンジンが実行できない AQL（COMPOSITION の uid への到達）は unexecutable として理由を持つ" do
    unsupported = "SELECT c/uid/value AS uid FROM EHR e CONTAINS COMPOSITION c"
    score = described_class.score(question(unsupported, [ [ "ProblemList" ] ]))

    expect(score.status).to eq(:unexecutable)
    expect(score.error).to include("unsupported path attribute")
  end

  it "コード値の条件（defining_code/code_string）は openehr 2.5.0 で実行でき、診断確度 at0074（疑い）の 2 件に一致する" do
    suspected = <<~AQL
      SELECT ev/data[at0001]/items[at0002]/value/value AS diagnosis
      FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
      WHERE ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {"at0074"}
    AQL

    expect(described_class.score(question(suspected, [ [ "高血圧症" ], [ "2型糖尿病" ] ])).status).to eq(:match)
  end

  it "採点対象の AQL を差し替えられる（S2・S4 が組んだ AQL を同じ採点器に渡す）" do
    score = described_class.score(question(SYSTOLIC_OVER_110, [ [ 120.0 ] ]), aql: SYSTOLIC_OVER_110.sub("> 110", "> 130"))

    expect(score).to have_attributes(status: :mismatch, rows: [], missing: [ [ 120.0 ] ])
  end
end
