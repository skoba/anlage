require "rails_helper"

# 評価 v2 の問いの読み込み（docs/design/s1-eval-v2-plan.md 2.1・2.2）。
# テストTODO:
# - v1 の seed をアダプタで読む（ゴールド本体は触らない）
# - v2 の YAML の必須キーと未知の kind／status
RSpec.describe Evaluation::Questions do
  describe ".from_v1_seed" do
    subject(:questions) { described_class.from_v1_seed(Rails.root.join("spec/fixtures/pathcards_eval_seed.yml")) }

    it "v1 の seed を card の問いとして読み、active 17 問・draft 1 問（q21）になり、match は archetype" do
      expect(questions).to all(have_attributes(kind: :card, match: :archetype))
      expect(questions.select(&:active?).size).to eq(17)
      expect(questions.select(&:draft?).map(&:id)).to eq([ "q21" ])
    end

    it "expected_archetype_id と expected_at_code を期待集合 1 要素に写し、intent_tag と notes を持ち越す" do
      q01 = questions.find { |question| question.id == "q01" }
      expect(q01.query).to eq("収縮期")
      expect(q01.expected).to eq([ { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" } ])
      expect(q01.forbidden).to eq([])
      expect(q01.intent_tag).to eq("bigram成立想定")
      expect(q01.notes).to include("wp3-log.md")

      q10 = questions.find { |question| question.id == "q10" }
      expect(q10.expected).to eq([ { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: nil } ])
    end
  end
end
