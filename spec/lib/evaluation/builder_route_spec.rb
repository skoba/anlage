require "rails_helper"

# 評価 v2 の S2 の経路（docs/design/s1-eval-v2-plan.md 8 節、R-20261124-21 の作業列 3）。
# 問いの selection からクエリビルダーが組んだ AQL を、参照 AQL と同じ採点器（期待行との照合）に通す。データは demo_initial。
RSpec.describe Evaluation::BuilderRoute do
  ROUTE_BP = { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" }.freeze

  before { Evaluation::Datasets.build("demo_initial") }

  def question(selection, expected_rows: [ [ 120.0 ] ])
    Evaluation::Question.new(id: "a001", kind: :aql, query: "収縮期血圧が 110 mmHg を超える記録", dataset: "demo_initial",
                             reference_aql: "SELECT 1", expected_rows: expected_rows, selection: selection)
  end

  it "selection から組んだ AQL が期待行を返せば match。組んだ AQL を持つ" do
    score = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ { card: ROUTE_BP, operator: ">", value: 110 } ] }))

    expect(score).to have_attributes(status: :match, missing: [], extra: [])
    expect(score.aql).to end_with("/items[at0004]/value/magnitude > 110")
  end

  it "期待行と違えば mismatch で、不足と余分の行が出る" do
    score = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ { card: ROUTE_BP, operator: ">", value: 130 } ] }))

    expect(score).to have_attributes(status: :mismatch, missing: [ [ 120.0 ] ], extra: [])
  end

  it "索引に無いカードを指す selection と、組めない selection は unbuildable で、理由を持つ" do
    missing = described_class.score(question({ columns: [ { archetype_id: "openEHR-EHR-CLUSTER.specimen.v1", at_code: "at0029" } ], conditions: [] }))
    invalid = described_class.score(question({ columns: [ ROUTE_BP ], conditions: [ { card: ROUTE_BP, operator: "CONTAINS", value: "1" } ] }))

    expect(missing).to have_attributes(status: :unbuildable, aql: nil)
    expect(missing.error).to include("openEHR-EHR-CLUSTER.specimen.v1", "at0029")
    expect(invalid).to have_attributes(status: :unbuildable)
    expect(invalid.error).to include("CONTAINS")
  end

  it "selection の無い問いは採点しない（nil）" do
    expect(described_class.score(question(nil))).to be_nil
  end
end
