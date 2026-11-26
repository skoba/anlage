require "rails_helper"

# 評価 v2 の S2 の経路（docs/design/s1-eval-v2-plan.md 8 節、R-20261124-21 の作業列 3）。
# 問いの selection からクエリビルダーが組んだ AQL を、参照 AQL と同じ採点器（期待行との照合）に通す。データは demo_initial。
RSpec.describe Evaluation::BuilderRoute do
  ROUTE_BP = { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" }.freeze

  before { Evaluation::Datasets.build("demo_initial") }

  def question(selection, expected_rows: [ [ 148.0 ], [ 152.0 ] ])
    Evaluation::Question.new(id: "a001", kind: :aql, query: "収縮期血圧が 140 mmHg 以上の記録", dataset: "demo_initial",
                             reference_aql: "SELECT 1", expected_rows: expected_rows, selection: selection)
  end

  it "selection から組んだ AQL が期待行を返せば match。組んだ AQL を持つ" do
    score = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ { card: ROUTE_BP, operator: ">=", value: 140 } ] }))

    expect(score).to have_attributes(status: :match, missing: [], extra: [])
    expect(score.aql).to end_with("/items[at0004]/value/magnitude >= 140")
  end

  it "期待行と違えば mismatch で、不足と余分の行が出る" do
    score = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ { card: ROUTE_BP, operator: ">=", value: 150 } ] }))

    expect(score).to have_attributes(status: :mismatch, missing: [ [ 148.0 ] ], extra: [])
  end

  it "索引に無いカードを指す selection と、組めない selection は unbuildable で、理由を持つ" do
    missing = described_class.score(question({ columns: [ { archetype_id: "openEHR-EHR-CLUSTER.specimen.v1", at_code: "at0029" } ], conditions: [] }))
    invalid = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ { card: ROUTE_BP, operator: "CONTAINS", value: "1" } ] }))

    expect(missing).to have_attributes(status: :unbuildable, aql: nil)
    expect(missing.error).to include("openEHR-EHR-CLUSTER.specimen.v1", "at0029")
    expect(invalid).to have_attributes(status: :unbuildable)
    expect(invalid.error).to include("CONTAINS")
  end

  # docs/design/s1-eval-v2-plan.md 8.4（R-20261125-6）。demo_initial（docs/design/sample-data-plan.md 3 節）の血圧 v2 は 11 件で、
  # 収縮期 130〜140 の中かつ拡張期 90 未満は 138／84 と 134／82 の 2 件。傷病の確定は 9 件、確度の記載が無いのは紹介状の 2 件
  it "どちらかを満たす（any）と範囲の外（OUTSIDE）の selection: 中のカードも索引から引いて組む" do
    diastolic = ROUTE_BP.merge(at_code: "at0005")
    either = { any: [ { card: ROUTE_BP, operator: "OUTSIDE", value: { low: 130, high: 140 } }, { card: diastolic, operator: ">=", value: 90 } ] }
    score = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ either ] },
                                           expected_rows: [ [ 148.0 ], [ 152.0 ], [ 88.0 ], [ 96.0 ], [ 104.0 ], [ 132.0 ], [ 128.0 ], [ 126.0 ], [ 118.0 ] ]))

    expect(score).to have_attributes(status: :match)
    expect(score.aql.lines.last).to match(%r{\AWHERE \(\(o/.+at0004\]/value/magnitude < 130 OR o/.+at0004\]/value/magnitude > 140\) OR o/.+at0005\]/value/magnitude >= 90\)\z})
  end

  it "未記入を含む（include_missing）の selection: 確定 9 行と、確度の記載が無い紹介状の 2 行" do
    pd = "openEHR-EHR-EVALUATION.problem_diagnosis.v1"
    selection = { columns: [ { archetype_id: pd, at_code: "at0002" } ],
                  conditions: [ { card: { archetype_id: pd, at_code: "at0073" }, operator: "MATCHES", value: [ "at0076" ], include_missing: true } ] }

    expected = [ [ "2型糖尿病" ], [ "2型糖尿病" ], [ "2型糖尿病" ], [ "糖尿病性腎症" ], [ "高血圧症" ], [ "高血圧症" ], [ "鉄欠乏性貧血" ],
                 [ "脂質異常症" ], [ "慢性腎臓病" ], [ "花粉症" ], [ "狭心症" ] ]

    expect(described_class.score(question(selection, expected_rows: expected))).to have_attributes(status: :match)
  end

  it "any の中の、索引に無いカードは unbuildable" do
    missing = { archetype_id: "openEHR-EHR-CLUSTER.specimen.v1", at_code: "at0029" }
    score = described_class.score(question({ columns: [ ROUTE_BP ],
                                             conditions: [ { any: [ { card: ROUTE_BP, operator: ">", value: 1 }, { card: missing, operator: "=", value: "x" } ] } ] }))

    expect(score).to have_attributes(status: :unbuildable)
    expect(score.error).to include("openEHR-EHR-CLUSTER.specimen.v1")
  end

  it "selection の無い問いは採点しない（nil）" do
    expect(described_class.score(question(nil))).to be_nil
  end

  # ゴールドに足す問いの案（spec/fixtures/evaluation/v2/aql_s2.yml、draft）の健全性。案の期待行は実測で、臨床のレビューは人間。
  # ゴールドに追随する spec 側の確認で、案が確定・変更されたら同じコミットで直す
  it "案（draft）の 3 問は、参照 AQL も、selection からビルダーが組んだ AQL も、期待行に一致する" do
    drafts = Evaluation::Questions.from_v2.select { |question| question.draft? && question.selection }

    expect(drafts.map(&:id)).to match_array(%w[a006 a007 a008])
    drafts.each do |draft|
      expect(Evaluation::AqlScorer.score(draft).status).to eq(:match), "#{draft.id} の参照 AQL"
      expect(described_class.score(draft)).to have_attributes(status: :match), "#{draft.id} の S2 の経路"
    end
  end
end
