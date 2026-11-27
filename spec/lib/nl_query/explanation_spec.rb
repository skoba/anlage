require "rails_helper"
require "support/nl_query_cards"

# 何をどう引いたかの説明（docs/design/s4-nl-aql-plan.md 1 節の 7）。選択とカードの文言から、決まった形で組む。
# LLM には書かせない。実行の結果（記録の中身）は入力に無いので、説明にも現れない。
RSpec.describe NlQuery::Explanation do
  include_context "nl_query のカード"

  def explain(**selection)
    described_class.build({ conditions: [], template_id: false, across_versions: false }.merge(selection))
  end

  it "表示する項目、条件、アーキタイプ、テンプレートを書く。値集合の条件は、表示名とコードの両方（a002）" do
    text = explain(columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [ "at0074" ] } ])

    expect(text).to eq(
      "「プロブレム・診断」の「プロブレム・診断名」を表示します。" \
      "条件: 「診断確度」が 疑い（at0074）。" \
      "アーキタイプ: openEHR-EHR-EVALUATION.problem_diagnosis.v1。テンプレート: ProblemList。"
    )
  end

  it "条件が無いとき、条件の文を書かない" do
    expect(explain(columns: [ systolic, diastolic ])).to eq(
      "「血圧」の「収縮期」「拡張期」を表示します。" \
      "アーキタイプ: openEHR-EHR-OBSERVATION.blood_pressure.v2。テンプレート: CardiologyEncounter。"
    )
  end

  it "数値の条件は、値と単位と、演算子の言葉で書く" do
    {
      ">=" => "「収縮期」が 140 mm[Hg] 以上", ">" => "「収縮期」が 140 mm[Hg] より大きい", "<" => "「収縮期」が 140 mm[Hg] 未満",
      "<=" => "「収縮期」が 140 mm[Hg] 以下", "=" => "「収縮期」が 140 mm[Hg] に等しい"
    }.each do |operator, phrase|
      expect(explain(columns: [ systolic ], conditions: [ { card: systolic, operator: operator, value: 140 } ])).to include("条件: #{phrase}。")
    end
  end

  it "範囲の外、日時の範囲、文字列の一致・含む・いずれか、未記入を含む" do
    text = explain(columns: [ diagnosis ], conditions: [
      { card: onset, operator: "BETWEEN", value: { from: "2025-01-01", to: "2026-01-01" } },
      { card: diagnosis, operator: "MATCHES", value: [ "2型糖尿病", "高血圧症" ] },
      { card: diagnosis, operator: "CONTAINS", value: "糖尿病" },
      { card: diagnosis, operator: "=", value: "狭心症" },
      { card: certainty, operator: "MATCHES", value: [ "at0074", "at0075" ], include_missing: true }
    ])

    expect(text).to include(
      "条件: 「発症日時」が 2025-01-01 以降、2026-01-01 より前、かつ、" \
      "「プロブレム・診断名」が「2型糖尿病」「高血圧症」のいずれか、かつ、" \
      "「プロブレム・診断名」が「糖尿病」を含む、かつ、" \
      "「プロブレム・診断名」が「狭心症」に一致、かつ、" \
      "「診断確度」が 疑い（at0074）、推定（at0075）のいずれか（未記入を含む）。"
    )
    expect(explain(columns: [ systolic ], conditions: [ { card: systolic, operator: "OUTSIDE", value: { low: 100, high: 140 } } ]))
      .to include("条件: 「収縮期」が 100 mm[Hg] より低い、または 140 mm[Hg] より高い。")
    expect(explain(columns: [ diagnosis ], conditions: [ { card: onset, operator: "BETWEEN", value: { from: "2025-01-01" } } ]))
      .to include("条件: 「発症日時」が 2025-01-01 以降。")
  end

  it "画面から来た、片方が空の日時の範囲（from や to が空の文字）は、ある側だけを書く" do
    expect(explain(columns: [ diagnosis ], conditions: [ { card: onset, operator: "BETWEEN", value: { from: "", to: "2026-01-01" } } ]))
      .to include("条件: 「発症日時」が 2026-01-01 より前。")
  end

  it "どちらかを満たすは、「または」でつなぎ、括弧でくくる" do
    text = explain(columns: [ systolic ], conditions: [
      { any: [ { card: systolic, operator: ">=", value: 140 }, { card: diastolic, operator: ">=", value: 90 } ] }
    ])

    expect(text).to include("条件: （「収縮期」が 140 mm[Hg] 以上、または、「拡張期」が 90 mm[Hg] 以上）。")
  end

  it "テンプレートも表示する、版をまたいで引く、を書く" do
    text = explain(columns: [ diagnosis ], template_id: true, across_versions: true)

    expect(text).to include("記録のテンプレートも表示します。")
    expect(text).to include("アーキタイプの版をまたいで引きます。")
  end

  it "同じ項目が 2 つのテンプレートにあるとき、テンプレートを並べる" do
    referral = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read)
    referral.pathcards = Opt::PathcardExtractor.call(referral).cards
    referral.save!
    other = card("jp_referral", "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0073")

    text = explain(columns: [ diagnosis ], conditions: [ { card: other, operator: "MATCHES", value: [ "at0074" ] } ])
    expect(text).to end_with("テンプレート: ProblemList、jp_referral。")
  end

  it "並べ替えを書く（skoba/anlage#242）" do
    expect(explain(columns: [ systolic ], order: { card: diastolic, direction: "desc" })).to include("「拡張期」の降順に並べます。")
    expect(explain(columns: [ systolic ], order: { card: systolic, direction: "asc" })).to include("「収縮期」の昇順に並べます。")
  end
end
