require "rails_helper"
require "support/nl_query_cards"

# 選択（SelectionParser の selection）を、クエリビルダーの画面の URL のパラメータに直す（docs/design/s4-nl-aql-plan.md 1 節:
# LLM が返した選択は、クエリビルダーの「表示する項目」「条件」にそのまま入る。利用者は、実行の前に見て、直せる）。
RSpec.describe NlQuery::QueryParams do
  include_context "nl_query のカード"

  def params(**selection)
    described_class.from({ conditions: [], template_id: false, across_versions: false }.merge(selection))
  end

  def ref(card) = QueryBuilder::Corpus.ref(card)

  it "表示する項目は、カードの参照の並びになる" do
    expect(params(columns: [ systolic, diastolic ])).to eq(columns: [ ref(systolic), ref(diastolic) ])
  end

  it "数値、範囲の外、値集合（未記入を含む）、日時の範囲、文字列の条件を、画面の入力の名前に直す" do
    result = params(columns: [ diagnosis ], template_id: true, across_versions: true, conditions: [
      { card: systolic, operator: ">=", value: 140 },
      { card: systolic, operator: "OUTSIDE", value: { low: 100, high: 139 } },
      { card: certainty, operator: "MATCHES", value: [ "at0074", "at0076" ], include_missing: true },
      { card: onset, operator: "BETWEEN", value: { from: "2025-01-01", to: "2026-01-01" } },
      { card: diagnosis, operator: "CONTAINS", value: "糖尿病" }
    ])

    expect(result).to eq(
      columns: [ ref(diagnosis) ], template_id: "1", across_versions: "1",
      conditions: {
        "0" => { card: ref(systolic), operator: ">=", value: "140" },
        "1" => { card: ref(systolic), operator: "OUTSIDE", low: "100", high: "139" },
        "2" => { card: ref(certainty), operator: "MATCHES", values: [ "at0074", "at0076" ], include_missing: "1" },
        "3" => { card: ref(onset), operator: "BETWEEN", from: "2025-01-01", to: "2026-01-01" },
        "4" => { card: ref(diagnosis), operator: "CONTAINS", value: "糖尿病" }
      }
    )
  end

  it "どちらかを満たすは、2 つめ以降の条件に「または」の印を付けて並べる" do
    result = params(columns: [ systolic ], conditions: [
      { card: diagnosis, operator: "=", value: "狭心症" },
      { any: [ { card: systolic, operator: ">=", value: 140 }, { card: diastolic, operator: ">=", value: 90 } ] }
    ])

    expect(result[:conditions]).to eq(
      "0" => { card: ref(diagnosis), operator: "=", value: "狭心症" },
      "1" => { card: ref(systolic), operator: ">=", value: "140" },
      "2" => { card: ref(diastolic), operator: ">=", value: "90", or: "1" }
    )
  end

  it "文字列のいずれか（MATCHES）は、画面に入力が無いので、一致の条件を「または」でつないだ形にする" do
    result = params(columns: [ diagnosis ], conditions: [ { card: diagnosis, operator: "MATCHES", value: [ "2型糖尿病", "高血圧症" ] } ])

    expect(result[:conditions]).to eq(
      "0" => { card: ref(diagnosis), operator: "=", value: "2型糖尿病" },
      "1" => { card: ref(diagnosis), operator: "=", value: "高血圧症", or: "1" }
    )
  end
end
