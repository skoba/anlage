require "rails_helper"

# skoba/anlage#33: coded_manual（DV_TEXT 代替なし・外部値集合のみ）は「用語サービス未接続」を
# 明示したテキスト入力＋system/code の任意欄。既存 fixture に該当 ELEMENT が無いので
# field ハッシュ直渡しで partial 単体を固定する。
RSpec.describe "templates/_field", type: :view do
  it "coded_manual は注記付きテキスト入力と system/code 欄を描く" do
    field = { "name" => "dx", "label" => "傷病名", "rm_type" => "DV_CODED_TEXT", "input_kind" => "coded_manual",
              "code_list" => [], "value_set_uri" => "terminology:http://id.who.int/icd/release/11/mms", "required" => false }

    render partial: "templates/field", locals: { field: field, disabled: false, value: nil, error: nil }

    expect(rendered).to match(/<input[^>]*type="text"[^>]*name="values\[dx\]"/)
    expect(rendered).to include("用語サービス未接続")
    expect(rendered).to include("http://id.who.int/icd/release/11/mms")
    expect(rendered).to match(/name="values\[dx__system\]"/)
    expect(rendered).to match(/name="values\[dx__code\]"/)
  end

  it "select は code_list を options にする（input_kind のみを読む）" do
    field = { "name" => "c", "label" => "確度", "rm_type" => "DV_CODED_TEXT", "input_kind" => "select",
              "code_list" => %w[at0074], "code_labels" => { "at0074" => "疑い" }, "required" => false }

    render partial: "templates/field", locals: { field: field, disabled: false, value: nil, error: nil }

    expect(rendered).to include('<option value="at0074" >疑い</option>')
  end

  # skoba/anlage#35: RM 型でネイティブ入力を切り替える（ja ロケールのブラウザが年/月/日を出す）
  it "date は type=date、time は type=time" do
    render partial: "templates/field", locals: { field: { "name" => "d", "label" => "日付", "rm_type" => "DV_DATE", "input_kind" => "date", "required" => false }, disabled: false, value: nil, error: nil }
    expect(rendered).to match(/<input[^>]*type="date"[^>]*name="values\[d\]"/)

    render partial: "templates/field", locals: { field: { "name" => "t", "label" => "時刻", "rm_type" => "DV_TIME", "input_kind" => "time", "required" => false }, disabled: false, value: nil, error: nil }
    expect(rendered).to match(/<input[^>]*type="time"[^>]*name="values\[t\]"/)
  end

  it "datetime は type=date と「時刻（任意）」の type=time の 2 入力" do
    render partial: "templates/field", locals: { field: { "name" => "dt", "label" => "発症日時", "rm_type" => "DV_DATE_TIME", "input_kind" => "datetime", "required" => false }, disabled: false, value: nil, error: nil }

    expect(rendered).to match(/<input[^>]*type="date"[^>]*name="values\[dt\]"/)
    expect(rendered).to match(/<input[^>]*type="time"[^>]*name="values\[dt__time\]"/)
    expect(rendered).to include("時刻（任意）")
  end

  # skoba/anlage#37: DV_QUANTITY は数値＋単位。単位は units リストから select、1 つなら固定表示、無ければ自由入力
  it "number は units リストが複数なら select、1 つなら固定表示、無ければ自由入力" do
    base = { "name" => "q", "label" => "値", "rm_type" => "DV_QUANTITY", "input_kind" => "number", "required" => false }

    render partial: "templates/field", locals: { field: base.merge("units_list" => [ "kg/m2", "[lb_av]/[in_i]2" ]), disabled: false, value: nil, error: nil }
    expect(rendered).to match(/<input[^>]*type="number"[^>]*name="values\[q\]"/)
    expect(rendered).to match(/<select[^>]*name="values\[q__units\]"[^>]*>.*kg\/m2.*<\/select>/m)

    render partial: "templates/field", locals: { field: base.merge("units_list" => [ "cm" ]), disabled: false, value: nil, error: nil }
    expect(rendered).to include('<span class="units">cm</span>')
    expect(rendered).to match(/<input[^>]*type="hidden"[^>]*name="values\[q__units\]"[^>]*value="cm"/)

    render partial: "templates/field", locals: { field: base.merge("units_list" => []), disabled: false, value: nil, error: nil }
    expect(rendered).to match(/<input[^>]*type="text"[^>]*name="values\[q__units\]"/)
  end
end
