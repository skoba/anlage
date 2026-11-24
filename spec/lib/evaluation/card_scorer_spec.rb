require "rails_helper"

# card の採点（docs/design/s1-eval-v2-plan.md 2.4）。カードは identity だけの最小形で、
# アーキタイプ ID と at-code は CardiologyEncounter／ProblemList の実物（spec/fixtures/pathcards/*.golden.json）。
RSpec.describe Evaluation::CardScorer do
  BP = "openEHR-EHR-OBSERVATION.blood_pressure.v2"
  PD = "openEHR-EHR-EVALUATION.problem_diagnosis.v1"

  def card(archetype_id, at_code)
    { "identity" => { "archetype_id" => archetype_id, "at_code" => at_code } }
  end

  let(:results) { [ card(PD, "at0002"), card(BP, "at0004"), card(PD, "at0003"), card(BP, "at0005") ] }

  it "期待集合の 1 つが 2 位なら rank 1、hit@1 なし、hit@3 あり、recall@3 は 1/2、逆順位 0.5" do
    question = Evaluation::Question.new(id: "c010", kind: :card, query: "血圧",
                                        expected: [ { archetype_id: BP, at_code: "at0004" }, { archetype_id: BP, at_code: "at0005" } ])
    score = described_class.score(question, results)

    expect(score).to have_attributes(rank: 1, hit_at_1: false, hit_at_3: true, recall_at_3: 0.5,
                                     reciprocal_rank: 0.5, complete_failure: false, violations: [])
  end

  it "match: archetype なら at_code を見ず、archetype_id の一致で rank を決める（v1 互換）" do
    question = Evaluation::Question.new(id: "q05", kind: :card, query: "診断", match: :archetype,
                                        expected: [ { archetype_id: PD, at_code: "at0077" } ])
    expect(described_class.score(question, results).rank).to eq(0)
  end

  it "match: card で at_code が無い期待要素は archetype の一致で見る" do
    question = Evaluation::Question.new(id: "c014", kind: :card, query: "血圧測定",
                                        expected: [ { archetype_id: BP, at_code: nil } ])
    expect(described_class.score(question, results).rank).to eq(1)
  end

  it "forbidden が top-3 に出たら負例違反に挙がり、4 位以下なら挙がらない" do
    question = Evaluation::Question.new(id: "c015", kind: :card, query: "臨床検査",
                                        expected: [ { archetype_id: BP, at_code: "at0004" } ],
                                        forbidden: [ { archetype_id: PD, at_code: "at0003" }, { archetype_id: BP, at_code: "at0005" } ])
    expect(described_class.score(question, results).violations).to eq([ { archetype_id: PD, at_code: "at0003" } ])
  end

  it "期待集合のどれも出なければ完全失敗（rank nil、逆順位 0、recall 0）" do
    question = Evaluation::Question.new(id: "q16", kind: :card, query: "BMI",
                                        expected: [ { archetype_id: "openEHR-EHR-OBSERVATION.body_mass_index.v2", at_code: "at0004" } ])
    expect(described_class.score(question, results)).to have_attributes(rank: nil, reciprocal_rank: 0.0, recall_at_3: 0.0, complete_failure: true)
  end
end
