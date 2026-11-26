require "rails_helper"

# 評価 v2 の問いの読み込み（docs/design/s1-eval-v2-plan.md 2.1・2.2）。
# テストTODO:
# - v1 の seed をアダプタで読む（ゴールド本体は触らない）
# - v2 の YAML の必須キーと未知の kind／status
RSpec.describe Evaluation::Questions do
  describe ".from_v1_seed" do
    subject(:questions) { described_class.from_v1_seed(Rails.root.join("spec/fixtures/pathcards_eval_seed.yml")) }

    # q21（既往歴、draft）は R-20261124-15 で v2 の c021 に移した。v1 は active 17 問だけになる
    it "v1 の seed を card の問いとして読み、active 17 問・draft 0 問になり、match は archetype" do
      expect(questions).to all(have_attributes(kind: :card, match: :archetype))
      expect(questions.select(&:active?).size).to eq(17)
      expect(questions.select(&:draft?)).to be_empty
      expect(questions.map(&:id)).not_to include("q21")
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

    # 版をまたぐ問い（docs/design/s1-eval-v2-plan.md 8.5、R-20261125-10）
    it "版ごとの参照 AQL（reference_aqls）と、selection の across_versions を読む" do
      write("aql.yml", <<~YAML)
        - id: x1
          kind: aql
          query: "版をまたいで、収縮期血圧が 140 以上"
          dataset: demo_initial
          reference_aqls:
            openEHR-EHR-OBSERVATION.blood_pressure.v1: "SELECT 1"
            openEHR-EHR-OBSERVATION.blood_pressure.v2: "SELECT 2"
          expected_rows: []
          selection:
            across_versions: true
            columns:
              - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
      YAML

      x1 = described_class.from_v2(dir).first

      expect(x1.reference_aqls).to eq("openEHR-EHR-OBSERVATION.blood_pressure.v1" => "SELECT 1", "openEHR-EHR-OBSERVATION.blood_pressure.v2" => "SELECT 2")
      expect(x1.reference_aql).to be_nil
      expect(x1.selection).to include(across_versions: true)
    end

    it "aql の問いは reference_aql か reference_aqls のどちらか 1 つを持つ。両方、どちらも無い、reference_aqls が表でない、は読み込みで止まる" do
      base = "id: x2, kind: aql, query: q, dataset: demo_initial, expected_rows: []"
      write("bad.yml", "- { #{base} }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x2.*reference_aql/)

      write("bad.yml", "- { #{base}, reference_aql: SELECT, reference_aqls: { a: SELECT } }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x2.*どちらか/)

      write("bad.yml", "- { #{base}, reference_aqls: [ SELECT ] }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /x2.*reference_aqls/)
    end

    # 負例だけの問い（docs/design/s1-eval-v2-plan.md 9 節、R-20261125-7）
    it "expected が空で forbidden を持つ card の問いは、負例だけの問いとして読む。at_code の無い負例はアーキタイプを指す" do
      write("cards.yml", <<~YAML)
        - id: n1
          kind: card
          query: "肥満度"
          expected: []
          forbidden:
            - { archetype_id: openEHR-EHR-OBSERVATION.body_mass_index.v2 }
        - id: p1
          kind: card
          query: "収縮期"
          expected:
            - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
      YAML

      negative, positive = described_class.from_v2(dir)

      expect(negative).to have_attributes(negative_only?: true, expected: [], status: :active,
                                          forbidden: [ { archetype_id: "openEHR-EHR-OBSERVATION.body_mass_index.v2", at_code: nil } ])
      expect(positive.negative_only?).to be(false)
    end

    it "expected も forbidden も空の card の問いは読み込みで止まる" do
      write("bad.yml", "- { id: n2, kind: card, query: q, expected: [] }\n")

      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /n2.*expected.*forbidden/)
    end

    # S2 の経路（R-20261124-21 の作業列 3、docs/design/s1-eval-v2-plan.md 8 節）: aql の問いは、クエリビルダーへの入力（selection）を持てる
    it "aql の問いの selection（表示する項目、条件、文書名）を読む。カードは archetype_id と at_code で指す" do
      write("aql.yml", <<~YAML)
        - id: a001
          kind: aql
          query: "収縮期血圧が 110 mmHg を超える記録"
          dataset: demo_initial
          reference_aql: "SELECT 1"
          expected_rows: [[120.0]]
          selection:
            columns:
              - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
            conditions:
              - card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
                operator: ">"
                value: 110
            composition_name: true
        - id: a002
          kind: aql
          query: "身長"
          dataset: demo_initial
          reference_aql: "SELECT 2"
          expected_rows: []
      YAML

      a001, a002 = described_class.from_v2(dir)
      bp = { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" }

      expect(a001.selection).to eq(columns: [ bp ], conditions: [ { card: bp, operator: ">", value: 110 } ], composition_name: true)
      expect(a002.selection).to be_nil
    end

    # docs/design/s1-eval-v2-plan.md 8.4（R-20261125-6）: クエリビルダーに足した 3 つの条件を、selection でも書ける
    it "selection の条件に、未記入を含む（include_missing）、範囲の外（OUTSIDE と low・high）、どちらかを満たす（any）を書ける" do
      write("aql.yml", <<~YAML)
        - id: a101
          kind: aql
          query: "確定の病名（確度の記載が無いものを含む）"
          dataset: demo_initial
          reference_aql: "SELECT 1"
          expected_rows: []
          selection:
            columns:
              - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0002 }
            conditions:
              - card: { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0073 }
                operator: MATCHES
                value: [at0076]
                include_missing: true
              - card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
                operator: OUTSIDE
                value: { low: 90, high: 140 }
              - any:
                  - { card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }, operator: ">=", value: 140 }
                  - { card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0005 }, operator: ">=", value: 90 }
      YAML

      certainty = { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: "at0073" }
      systolic = { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" }
      diastolic = systolic.merge(at_code: "at0005")

      expect(described_class.from_v2(dir).first.selection.fetch(:conditions)).to eq([
        { card: certainty, operator: "MATCHES", value: [ "at0076" ], include_missing: true },
        { card: systolic, operator: "OUTSIDE", value: { low: 90, high: 140 } },
        { any: [ { card: systolic, operator: ">=", value: 140 }, { card: diastolic, operator: ">=", value: 90 } ] }
      ])
    end

    it "any が配列でない、any の中の条件に card・operator が無い問いは読み込みで止まる" do
      base = "id: s2, kind: aql, query: q, dataset: demo_initial, reference_aql: SELECT, expected_rows: []"
      columns = "columns: [ { archetype_id: a, at_code: at0001 } ]"
      write("bad.yml", "- { #{base}, selection: { #{columns}, conditions: [ { any: 1 } ] } }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /s2.*any/)

      write("bad.yml", "- { #{base}, selection: { #{columns}, conditions: [ { any: [ { value: 1 } ] } ] } }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /s2.*card/)
    end

    it "selection に columns が無い、条件に card・operator が無い問いは読み込みで止まる" do
      base = "id: s1, kind: aql, query: q, dataset: demo_initial, reference_aql: SELECT, expected_rows: []"
      write("bad.yml", "- { #{base}, selection: { conditions: [] } }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /s1.*columns/)

      write("bad.yml", "- { #{base}, selection: { columns: [ { archetype_id: a, at_code: at0001 } ], conditions: [ { value: 1 } ] } }\n")
      expect { described_class.from_v2(dir) }.to raise_error(Evaluation::Questions::InvalidQuestion, /s1.*card/)
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

  # ゴールド v2（spec/fixtures/evaluation/v2/）。臨床レビュー（Kobayashi, Shinji、2026-11-24）の結果を R-20261124-15 で確定した。
  # ゴールド本体は人間の専有領域で、ここは確定した内容の写し（ゴールドに追随する）
  describe "確定したゴールド v2（R-20261124-15）" do
    subject(:questions) { described_class.from_v2.index_by(&:id) }

    PD_ID = "openEHR-EHR-EVALUATION.problem_diagnosis.v1"

    # a006〜a008 は S2 の経路の案（draft、人間レビュー前。R-20261124-21 の作業列 3）。
    # 2026-11-25 に card の 9 問（c022〜c024・c026・c027・c029〜c032）と保留問 c033 を足した（R-20261125-7。レビュー済み）。
    # c034「肥満度」は負例だけの問い。R-20261125-11 で active にした（採点に入れる）
    # 2026-11-26 に、S2 の経路つきの aql 7 問（a006、a009〜a014）を確定した（R-20261126-5）。draft は無くなった
    it "確定した 29 問: active 26 問（card 13・負例だけの card 1・aql 12）、pending 3 問（c019・c021・c033）。draft は無い" do
      cards = %w[c008 c010 c014 c015 c022 c023 c024 c026 c027 c029 c030 c031 c032 c034]
      aqls = %w[a001 a002 a003 a004 a005 a006 a009 a010 a011 a012 a013 a014]
      expect(questions.values.select(&:active?).map(&:id)).to match_array(cards + aqls)
      expect(questions.values.select(&:pending?).map(&:id)).to match_array(%w[c019 c021 c033])
      expect(questions.values.select(&:draft?)).to be_empty
      expect(questions.values.select(&:aql?)).to all(have_attributes(selection: be_present))
    end

    it "2026-11-26 に確定した aql の 7 問は、レビューの記録（Kobayashi, Shinji、2026-11-26）を持つ。a014 は版ごとの参照 AQL を持つ" do
      raw = YAML.load_file(Rails.root.join("spec/fixtures/evaluation/v2/aql_s2.yml"), permitted_classes: [ Date ])

      expect(raw.map { |entry| entry["id"] }).to eq(%w[a006 a009 a010 a011 a012 a013 a014])
      expect(raw.map { |entry| entry.values_at("reviewed_by", "reviewed_at") }.uniq).to eq([ [ "Kobayashi, Shinji", Date.new(2026, 11, 26) ] ])
      expect(questions.fetch("a014").reference_aqls.keys)
        .to eq(%w[openEHR-EHR-OBSERVATION.blood_pressure.v1 openEHR-EHR-OBSERVATION.blood_pressure.v2])
      expect(questions.fetch("a014").selection).to include(across_versions: true)
    end

    it "2026-11-25 に足した 9 問と c033 は、レビューの記録（Kobayashi, Shinji、2026-11-25）を持つ。c026 は診断確度が第 1 候補で、診断名は許容" do
      added = %w[c022 c023 c024 c026 c027 c029 c030 c031 c032 c033 c034]
      raw = YAML.load_file(Rails.root.join("spec/fixtures/evaluation/v2/cards.yml"), permitted_classes: [ Date ]).index_by { |entry| entry["id"] }

      expect(added.map { |id| raw.fetch(id).values_at("reviewed_by", "reviewed_at") }.uniq).to eq([ [ "Kobayashi, Shinji", Date.new(2026, 11, 25) ] ])
      expect(questions.fetch("c026")).to have_attributes(expected: [ { archetype_id: PD_ID, at_code: "at0073", rank: 1 } ],
                                                         acceptable: [ { archetype_id: PD_ID, at_code: "at0002" } ])
      expect(questions.fetch("c027").expected).to eq([ { archetype_id: PD_ID, at_code: "at0003" } ])
    end

    # R-20261125-11: カードの説明に「最高値」「最低値」があり、字面で届く。種類を「bigram成立想定」に直した
    it "c031「最高血圧」・c032「最低血圧」の種類は「bigram成立想定」。notes に、説明の「最高値」「最低値」に当たることが書いてある" do
      expect(%w[c031 c032].map { |id| questions.fetch(id).intent_tag }).to eq(%w[bigram成立想定 bigram成立想定])
      expect(questions.fetch("c031").notes).to include("最高値")
      expect(questions.fetch("c032").notes).to include("最低値")
      expect(%w[c031 c032].map { |id| questions.fetch(id).notes }).to all(satisfy { |notes| !notes.include?("根拠としては扱わない") })
    end

    it "c034「肥満度」: 負例だけの問い（active）。負例は body_mass_index.v2 のどのカードも" do
      expect(questions.fetch("c034")).to have_attributes(
        status: :active, negative_only?: true, forbidden: [ { archetype_id: "openEHR-EHR-OBSERVATION.body_mass_index.v2", at_code: nil } ]
      )
    end

    it "c008「発症」: 第 1 候補は発症日時（at0077）、第 2 候補はプロブレム・診断名（at0002）" do
      expect(questions.fetch("c008").expected).to eq([
        { archetype_id: PD_ID, at_code: "at0077", rank: 1 }, { archetype_id: PD_ID, at_code: "at0002", rank: 2 }
      ])
    end

    it "c015「臨床検査」: 第 1 候補は laboratory_test_result（archetype 一致）、負例は problem_diagnosis の at0003、許容の ID はまだ無い" do
      expect(questions.fetch("c015")).to have_attributes(
        match: :archetype,
        expected: [ { archetype_id: "openEHR-EHR-OBSERVATION.laboratory_test_result.v1", at_code: nil, rank: 1 } ],
        forbidden: [ { archetype_id: PD_ID, at_code: "at0003" } ],
        acceptable: []
      )
    end

    it "c021「既往歴」: story の at0004 と problem_diagnosis（archetype 一致）が同じ順位の正解で、負例は無い。pending のまま" do
      expect(questions.fetch("c021")).to have_attributes(
        status: :pending,
        expected: [
          { archetype_id: "openEHR-EHR-OBSERVATION.story.v1", at_code: "at0004", rank: 1 },
          { archetype_id: PD_ID, at_code: nil, rank: 1 }
        ],
        forbidden: []
      )
    end

    it "a002「診断確度が『疑い』」: コード値（value/defining_code/code_string）の一致で引く" do
      expect(questions.fetch("a002").reference_aql).to include("items[at0073]/value/defining_code/code_string", "at0074")
    end
  end
end
