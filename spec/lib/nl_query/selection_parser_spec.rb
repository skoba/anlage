require "rails_helper"
require "support/nl_query_cards"

# LLM の応答（JSON の文字列）を、クエリビルダーの選択に直して検査する（docs/design/s4-nl-aql-plan.md 2.1・2.3）。
# LLM が出すのは、カードの番号、演算子、値だけ。パス・型・値集合のコードは、番号から引いたカードが持つ。
# 例外は外に出さない。結果は ok（選択がある）／unanswerable（LLM が答えられないと返した）／rejected（検査ではねた）。
RSpec.describe NlQuery::SelectionParser do
  include_context "nl_query のカード"

  def parse(response)
    described_class.parse(response.is_a?(String) ? response : JSON.generate(response), cards: candidates)
  end

  describe "選択を作る" do
    it "番号と演算子と値から、クエリビルダーの選択（カード、演算子、値）を作る" do
      result = parse(columns: [ 1 ], conditions: [ { card: 1, operator: ">=", value: 140 } ])

      expect(result).to be_ok
      expect(result.selection[:columns]).to eq([ systolic ])
      expect(result.selection[:conditions]).to eq([ { card: systolic, operator: ">=", value: 140 } ])
      expect(result.selection).to include(template_id: false, across_versions: false)
    end

    it "作った選択から、クエリビルダーが参照 AQL と同じ形の AQL を組める（a001）" do
      selection = parse(columns: [ 1 ], conditions: [ { card: 1, operator: ">=", value: 140 } ]).selection

      aql = QueryBuilder::Builder.build(columns: selection[:columns], conditions: selection[:conditions])
      expect(aql).to eq(<<~AQL.chomp)
        SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude
        FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
        WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude >= 140
      AQL
    end

    it "値集合の条件は、表示名からコードをカードで引く（「疑い」→ at0074）" do
      result = parse(columns: [ 3 ], conditions: [ { card: 4, operator: "MATCHES", value: [ "疑い" ] } ])

      expect(result).to be_ok
      expect(result.selection[:conditions]).to eq([ { card: certainty, operator: "MATCHES", value: [ "at0074" ] } ])
    end

    it "値集合の条件の「未記入を含む」を受ける" do
      result = parse(columns: [ 3 ], conditions: [ { card: 4, operator: "MATCHES", value: [ "確定" ], include_missing: true } ])

      expect(result.selection[:conditions]).to eq([ { card: certainty, operator: "MATCHES", value: [ "at0076" ], include_missing: true } ])
    end

    it "LLM がコードやパスを書き足しても、使わない" do
      result = parse(columns: [ 3 ],
                     conditions: [ { card: 4, operator: "MATCHES", value: [ "疑い" ], code: "at0076", path: "/content/x" } ])

      expect(result.selection[:conditions]).to eq([ { card: certainty, operator: "MATCHES", value: [ "at0074" ] } ])
    end

    it "日時の範囲、文字列のいずれか、範囲の外、どちらかを満たす、を受ける" do
      result = parse(columns: [ 3, 5 ], template_id: true, conditions: [
        { card: 5, operator: "BETWEEN", value: { from: "2025-01-01", to: "2026-01-01" } },
        { card: 3, operator: "MATCHES", value: [ "2型糖尿病", "高血圧症" ] },
        { any: [ { card: 3, operator: "CONTAINS", value: "糖尿病" }, { card: 4, operator: "MATCHES", value: [ "確定" ] } ] }
      ])

      expect(result).to be_ok
      expect(result.selection[:template_id]).to be(true)
      expect(result.selection[:conditions]).to eq([
        { card: onset, operator: "BETWEEN", value: { from: "2025-01-01", to: "2026-01-01" } },
        { card: diagnosis, operator: "MATCHES", value: [ "2型糖尿病", "高血圧症" ] },
        { any: [ { card: diagnosis, operator: "CONTAINS", value: "糖尿病" }, { card: certainty, operator: "MATCHES", value: [ "at0076" ] } ] }
      ])

      outside = parse(columns: [ 1 ], conditions: [ { card: 1, operator: "OUTSIDE", value: { low: 100, high: 140 } } ])
      expect(outside.selection[:conditions]).to eq([ { card: systolic, operator: "OUTSIDE", value: { low: 100, high: 140 } } ])
    end

    it "JSON の前後に、コードの囲みや文が付いていても読む" do
      result = parse(%(```json\n{"columns": [1], "conditions": []}\n```))

      expect(result).to be_ok
      expect(result.selection[:columns]).to eq([ systolic ])
    end
  end

  describe "はねる（rejected。理由を返す。例外を外に出さない）" do
    it "候補に無い番号" do
      result = parse(columns: [ 9 ], conditions: [])

      expect(result).to be_rejected
      expect(result.reason).to include("候補に無い番号").and include("9")
    end

    it "番号でないもの（項目名、パス）でカードを指した" do
      expect(parse(columns: [ "収縮期" ], conditions: [])).to be_rejected
      expect(parse(columns: [ 1 ], conditions: [ { card: systolic.dig("identity", "path"), operator: ">", value: 1 } ])).to be_rejected
    end

    it "カードの型に合わない演算子" do
      result = parse(columns: [ 1 ], conditions: [ { card: 1, operator: "CONTAINS", value: "140" } ])

      expect(result).to be_rejected
      expect(result.reason).to include("収縮期").and include("CONTAINS")
    end

    it "値集合に無い表示名（コードを書いてきたときも）" do
      result = parse(columns: [ 3 ], conditions: [ { card: 4, operator: "MATCHES", value: [ "たぶん" ] } ])
      expect(result).to be_rejected
      expect(result.reason).to include("診断確度").and include("たぶん")

      expect(parse(columns: [ 3 ], conditions: [ { card: 4, operator: "MATCHES", value: [ "at0074" ] } ])).to be_rejected
    end

    it "数値でない値、日付でない値、空の値" do
      expect(parse(columns: [ 1 ], conditions: [ { card: 1, operator: ">=", value: "高い" } ])).to be_rejected
      expect(parse(columns: [ 5 ], conditions: [ { card: 5, operator: "BETWEEN", value: { from: "去年" } } ])).to be_rejected
      expect(parse(columns: [ 3 ], conditions: [ { card: 3, operator: "=", value: "" } ])).to be_rejected
    end

    it "未記入を含むを、値集合でない条件に付けた" do
      expect(parse(columns: [ 1 ], conditions: [ { card: 1, operator: ">=", value: 140, include_missing: true } ])).to be_rejected
    end

    it "どちらかを満たすの中が 1 つ、または入れ子" do
      one = { any: [ { card: 1, operator: ">=", value: 140 } ] }
      nested = { any: [ { card: 1, operator: ">=", value: 140 }, { any: [ { card: 1, operator: "<", value: 90 }, { card: 2, operator: "<", value: 60 } ] } ] }

      expect(parse(columns: [ 1 ], conditions: [ one ])).to be_rejected
      expect(parse(columns: [ 1 ], conditions: [ nested ])).to be_rejected
    end

    it "JSON として読めない応答" do
      result = parse("収縮期が 140 以上の記録を引きます。")

      expect(result).to be_rejected
      expect(result.reason).to include("JSON として読めない")
    end

    it "決まった形でない応答（配列、columns が配列でない、条件が形になっていない）" do
      expect(parse("[1, 2]")).to be_rejected
      expect(parse(columns: 1, conditions: [])).to be_rejected
      expect(parse(columns: [ 1 ], conditions: [ "収縮期 >= 140" ])).to be_rejected
      expect(parse(columns: [ 1 ], conditions: [ { card: 1 } ])).to be_rejected
    end

    it "表示する項目が無く、理由も無い" do
      expect(parse(columns: [], conditions: [])).to be_rejected
    end

    it "応答が無い（nil、空）" do
      expect(described_class.parse(nil, cards: candidates)).to be_rejected
      expect(described_class.parse("", cards: candidates)).to be_rejected
    end
  end

  describe "答えられない（unanswerable）" do
    it "選択が空で、理由があるとき、理由をそのまま返す" do
      result = parse(columns: [], conditions: [], reason: "候補の項目に、体重がありません。")

      expect(result).to be_unanswerable
      expect(result.selection).to be_nil
      expect(result.reason).to eq("候補の項目に、体重がありません。")
    end
  end
end
