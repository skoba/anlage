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
end
