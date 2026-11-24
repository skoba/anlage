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

  describe ".from_v2" do
    let(:dir) { Pathname.new(Dir.mktmpdir) }

    def write(name, yaml)
      dir.join(name).write(yaml)
    end

    it "card と aql の問いを読み、status は既定 active、match は既定 card、pending は pending_until を持つ" do
      write("cards.yml", <<~YAML)
        - id: c010
          kind: card
          query: "血圧"
          expected:
            - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
            - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0005 }
          forbidden:
            - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1 }
          intent_tag: bigram成立想定
        - id: c019
          kind: card
          status: pending
          query: "検体"
          expected: [ { archetype_id: openEHR-EHR-CLUSTER.specimen.v1 } ]
          pending_until: "CLUSTER.specimen を含む OPT がコーパスに入る"
      YAML
      write("aql.yml", <<~YAML)
        - id: a001
          kind: aql
          status: draft
          query: "収縮期血圧が 110 mmHg を超える記録"
          dataset: demo_initial
          reference_aql: "SELECT o FROM EHR e CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]"
          expected_rows: [[120.0]]
          cards: [ { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 } ]
      YAML

      questions = described_class.from_v2(dir)

      expect(questions.map(&:id)).to eq([ "a001", "c010", "c019" ])
      c010 = questions.find { |question| question.id == "c010" }
      expect(c010).to have_attributes(kind: :card, status: :active, match: :card, intent_tag: "bigram成立想定")
      expect(c010.expected.size).to eq(2)
      expect(c010.forbidden).to eq([ { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: nil } ])
      c019 = questions.find { |question| question.id == "c019" }
      expect(c019).to have_attributes(status: :pending, pending_until: a_string_including("specimen"))
      a001 = questions.find { |question| question.id == "a001" }
      expect(a001).to have_attributes(kind: :aql, status: :draft, dataset: "demo_initial", expected_rows: [ [ 120.0 ] ], ordered: false)
      expect(a001.reference_aql).to start_with("SELECT o")
      expect(a001.cards).to eq([ { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" } ])
    end

    it "expected の rank（順位。同じ順位を複数に付けてよい）と acceptable（許容）を読む。rank の無い問いは rank を持たない" do
      write("cards.yml", <<~YAML)
        - id: c008
          kind: card
          query: "発症"
          expected:
            - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0077, rank: 1 }
            - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0002, rank: 2 }
          acceptable:
            - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0003 }
        - id: c010
          kind: card
          query: "血圧"
          expected:
            - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
      YAML

      c008, c010 = described_class.from_v2(dir)

      expect(c008.expected).to eq([
        { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: "at0077", rank: 1 },
        { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: "at0002", rank: 2 }
      ])
      expect(c008.acceptable).to eq([ { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: "at0003" } ])
      expect(c010.expected).to eq([ { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" } ])
      expect(c010.acceptable).to eq([])
    end

    it "rank が 1 以上の整数でない問い、rank のある要素と無い要素が混ざる問いは読み込みで止まる" do
      pd = "openEHR-EHR-EVALUATION.problem_diagnosis.v1"
      write("bad.yml", "- { id: r1, kind: card, query: q, expected: [ { archetype_id: #{pd}, at_code: at0077, rank: 0 } ] }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /r1.*rank/)

      write("bad.yml", "- { id: r2, kind: card, query: q, expected: [ { archetype_id: #{pd}, at_code: at0077, rank: first } ] }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /r2.*rank/)

      write("bad.yml", "- { id: r3, kind: card, query: q, expected: [ { archetype_id: #{pd}, at_code: at0077, rank: 1 }, { archetype_id: #{pd}, at_code: at0002 } ] }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /r3.*rank/)
    end

    it "kind ごとの必須キーを欠く問い、未知の kind・status・match は読み込みで止まる" do
      write("bad_card.yml", "- { id: x1, kind: card, query: 血圧 }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x1.*expected/)

      write("bad_card.yml", "- { id: x2, kind: aql, query: q, dataset: demo_initial, reference_aql: SELECT }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x2.*expected_rows/)

      write("bad_card.yml", "- { id: x3, kind: table, query: q }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x3.*kind/)

      write("bad_card.yml", "- { id: x4, kind: card, status: maybe, query: q, expected: [ { archetype_id: a } ] }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x4.*status/)

      write("bad_card.yml", "- { id: x5, kind: card, match: fuzzy, query: q, expected: [ { archetype_id: a } ] }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x5.*match/)
    end
  end
end
