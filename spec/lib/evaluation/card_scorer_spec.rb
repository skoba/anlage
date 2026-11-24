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

  # 順位と許容（docs/design/s1-eval-v2-plan.md 7 節、R-20261124-15）。
  # results の並び: PD at0002（1 位）、BP at0004、PD at0003、BP at0005
  describe "順位（expected の rank）" do
    def ranked(first, second)
      Evaluation::Question.new(id: "c008", kind: :card, query: "発症",
                               expected: [ first.merge(rank: 1), second.merge(rank: 2) ])
    end

    it "第 1 候補が第 2 候補より先に出れば、順位の組 1 つが守られる" do
      score = described_class.score(ranked({ archetype_id: PD, at_code: "at0002" }, { archetype_id: PD, at_code: "at0003" }), results)
      expect(score).to have_attributes(order_pairs: 1, order_pairs_kept: 1, order_kept: true)
    end

    it "第 2 候補が先に出れば守られない（hit@1 は期待集合のどれかで成立したまま）" do
      score = described_class.score(ranked({ archetype_id: PD, at_code: "at0003" }, { archetype_id: PD, at_code: "at0002" }), results)
      expect(score).to have_attributes(order_pairs: 1, order_pairs_kept: 0, order_kept: false, hit_at_1: true)
    end

    it "第 2 候補が結果に出なくても、第 1 候補が出ていれば守られる" do
      score = described_class.score(ranked({ archetype_id: PD, at_code: "at0003" }, { archetype_id: PD, at_code: "at0077" }), results)
      expect(score).to have_attributes(order_pairs: 1, order_pairs_kept: 1, order_kept: true)
    end

    it "第 1 候補が出なければ守られない（第 2 候補だけ出る、両方出ない）" do
      only_second = described_class.score(ranked({ archetype_id: PD, at_code: "at0077" }, { archetype_id: PD, at_code: "at0002" }), results)
      neither = described_class.score(ranked({ archetype_id: PD, at_code: "at0077" }, { archetype_id: PD, at_code: "at0073" }), results)
      expect(only_second).to have_attributes(order_pairs_kept: 0, order_kept: false)
      expect(neither).to have_attributes(order_pairs_kept: 0, order_kept: false, complete_failure: true)
    end

    it "同じ順位どうしは組にしない: 1 位が 2 つ・2 位が 1 つなら組は 2 つ" do
      question = Evaluation::Question.new(id: "x", kind: :card, query: "血圧", expected: [
        { archetype_id: BP, at_code: "at0004", rank: 1 }, { archetype_id: BP, at_code: "at0005", rank: 1 },
        { archetype_id: PD, at_code: "at0003", rank: 2 }
      ])
      # at0004（2 位）は PD at0003（3 位）より先、at0005（4 位）は後
      expect(described_class.score(question, results)).to have_attributes(order_pairs: 2, order_pairs_kept: 1, order_kept: false)
    end

    it "rank の無い問いは全要素が同じ順位: 順位の組は 0 で、順位遵守は対象外（nil）" do
      question = Evaluation::Question.new(id: "c010", kind: :card, query: "血圧",
                                          expected: [ { archetype_id: BP, at_code: "at0004" }, { archetype_id: BP, at_code: "at0005" } ])
      expect(described_class.score(question, results)).to have_attributes(order_pairs: 0, order_pairs_kept: 0, order_kept: nil,
                                                                          rank: 1, recall_at_3: 0.5)
    end
  end

  describe "許容（acceptable）" do
    it "top-3 に出ても hit にも負例違反にもならず、許容の出現に挙がる。4 位以下は挙がらない" do
      question = Evaluation::Question.new(id: "c015", kind: :card, query: "臨床検査",
                                          expected: [ { archetype_id: "openEHR-EHR-OBSERVATION.laboratory_test_result.v1", at_code: nil } ],
                                          acceptable: [ { archetype_id: PD, at_code: "at0002" }, { archetype_id: BP, at_code: "at0005" } ])
      score = described_class.score(question, results)

      expect(score).to have_attributes(hit_at_3: false, complete_failure: true, violations: [])
      expect(score.acceptables).to eq([ { archetype_id: PD, at_code: "at0002" } ])
    end
  end
end
