require "rails_helper"

# 試行（1 つの問い・1 つの腕・1 回の応答）の採点（計画書 5.3 節・12 節。R-20261127-32）。
#   status: :match（行の一致。列の順を見る。主の指標）／:overlooked（見落とし。血圧の片方の版だけ）／:mismatch／
#           :lint（リンタで落ちた。実行しない）／:unexecutable／:unparseable（決まった形として読めない、答えられないと返した）
#   order_free: 列の順を見ない一致（副の指標）
# 応答は、spec に手で書いたもの（モデルの応答ではない）。
RSpec.describe Evaluation::Grounding::Scorer do
  before { Evaluation::Datasets.build("demo_initial") }

  let(:corpus) { QueryBuilder::Corpus.active }
  let(:queries) { Evaluation::Grounding::Queries.load.index_by(&:id) }

  BP_V2 = <<~AQL.squish.freeze
    SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude
    FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
    WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude >= 140
  AQL
  BP_V1 = BP_V2.sub("blood_pressure.v2", "blood_pressure.v1").freeze
  ONSET = <<~AQL.squish.freeze
    SELECT ev/data[at0001]/items[at0002]/value/value, ev/data[at0001]/items[at0077]/value/value, c/archetype_details/template_id/value
    FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
    WHERE ev/data[at0001]/items[at0077]/value/value >= "2025-01-01" AND ev/data[at0001]/items[at0077]/value/value < "2026-01-01"
  AQL

  def score(id, arm, response)
    described_class.score(queries.fetch(id), arm: arm, response: response.is_a?(String) ? response : JSON.generate(response), corpus: corpus)
  end

  describe "AQL を書かせる腕" do
    it "両方の版の AQL を返すと match。片方だけだと overlooked（見落とし）" do
      both = score("n001-1", :g_aql, aqls: [ BP_V1, BP_V2 ])
      one = score("n001-1", :g_aql, aqls: [ BP_V2 ])

      expect(both.status).to eq(:match)
      expect(both).to have_attributes(parseable: true, lint_ok: true, executed: true, order_free: true)
      expect(one.status).to eq(:overlooked)
    end

    it "名指しの文は、名指ししたテンプレートの行だけが正解" do
      expect(score("n001-4", :g_aql, aqls: [ BP_V2 ]).status).to eq(:match)
      expect(score("n001-4", :g_aql, aqls: [ BP_V1, BP_V2 ]).status).to eq(:mismatch)
    end

    it "列の順が違うだけの答えは、主の指標では mismatch、副の指標（列の順を見ない）では一致" do
      result = score("n013-1", :n1, aqls: [ ONSET ])

      expect(result.status).to eq(:mismatch)
      expect(result.order_free).to be(true)
    end

    it "AQL の文字だけの応答、コードの囲みつきの応答も読む" do
      expect(score("n001-4", :n0, BP_V2).status).to eq(:match)
      expect(score("n001-4", :n0, "```json\n#{JSON.generate(aqls: [ BP_V2 ])}\n```").status).to eq(:match)
    end

    it "リンタの error がある AQL は、実行せず lint。どれか 1 本でもあれば、どれも実行しない" do
      bad = BP_V2.sub("items[at0004]/value/magnitude >= 140", "items[at0099]/value/magnitude >= 140")
      expect(OpenehrRails::Aql::Executor).not_to receive(:execute)

      result = score("n001-1", :g_aql, aqls: [ BP_V1, bad ])
      expect(result.status).to eq(:lint)
      expect(result).to have_attributes(lint_ok: false, executed: false, order_free: false)
    end

    it "読めない応答、AQL が 1 本も無い応答は unparseable" do
      expect(score("n001-1", :n0, "分かりません。").status).to eq(:unparseable)
      expect(score("n001-1", :n0, aqls: []).status).to eq(:unparseable)
      expect(score("n001-1", :n0, "").status).to eq(:unparseable)
    end
  end

  describe "選択を出す腕（G-選択）" do
    let(:candidates) { NlQuery::Candidates.call(queries["n001-1"].nl_query, corpus: corpus) }

    def number(template_id, label, question_id = "n001-1")
      cards = NlQuery::Candidates.call(queries[question_id].nl_query, corpus: corpus)
      cards.index { |card| card.dig("identity", "template_id") == template_id && card.dig("semantics", "labels", 0, "text") == label } + 1
    end

    it "版をまたぐ選択（across_versions）で、両方の版の行が返れば match。版の列は、落として比べる" do
      systolic = number("CardiologyEncounter", "収縮期")
      result = score("n001-1", :g_selection, columns: [ systolic ], conditions: [ { card: systolic, operator: ">=", value: 140 } ], across_versions: true)

      expect(result.status).to eq(:match)
      expect(result.card_match).to be(true)
    end

    it "片方の版だけの選択は overlooked" do
      systolic = number("CardiologyEncounter", "収縮期")
      result = score("n001-1", :g_selection, columns: [ systolic ], conditions: [ { card: systolic, operator: ">=", value: 140 } ])

      expect(result.status).to eq(:overlooked)
    end

    it "もとから版をまたぐ問い（a014 の文）は、版の列を落とさずに比べる" do
      systolic = number("CardiologyEncounter", "収縮期", "n014-1")
      result = score("n014-1", :g_selection, columns: [ systolic ], conditions: [ { card: systolic, operator: ">=", value: 140 } ], across_versions: true)

      expect(result.status).to eq(:match)
    end

    it "違うカードを選ぶと mismatch で、カードの一致も偽" do
      diastolic = number("CardiologyEncounter", "拡張期")
      result = score("n001-1", :g_selection, columns: [ diastolic ], conditions: [ { card: diastolic, operator: ">=", value: 140 } ], across_versions: true)

      expect(result.status).to eq(:mismatch)
      expect(result.card_match).to be(false)
    end

    it "検査ではねた選択、答えられないと返した応答は unparseable。理由が付く" do
      rejected = score("n001-1", :g_selection, columns: [ 999 ], conditions: [])
      unanswerable = score("n001-1", :g_selection, columns: [], conditions: [], reason: "分かりません。")

      expect(rejected.status).to eq(:unparseable)
      expect(rejected.reason).to include("候補に無い番号")
      expect(unanswerable.status).to eq(:unparseable)
    end

    it "クエリビルダーが組めない選択は lint（実行しない）" do
      systolic = number("CardiologyEncounter", "収縮期")
      diagnosis = number("ProblemList", "プロブレム・診断名")

      expect(score("n001-1", :g_selection, columns: [ systolic, diagnosis ], conditions: []).status).to eq(:lint)
    end
  end
end
