require "rails_helper"

# skoba/anlage#34（解決形 (a) bug）: 実ブラウザで任意項目を空欄のまま送信すると
# CompositionBuilder#dv_date_time が nil.iso8601 で 500。空欄の要素は Composition に
# 含めず、OPT の occurrences 下限 ≥1 の要素が空なら 422 で説明する。
RSpec.describe "空欄の任意項目を含む Composition の保存（#34）", type: :request do
  before { select_patient } # skoba/anlage#161: 記録は、患者を選んでから保存する（spec/support/patient_selection.rb）

  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }

  # 2026-09-25 の実ブラウザ送信で 500 になった実パラメータ（at0030／at0073 が空）
  let(:real_params) do
    { "problem_diagnosis_at0002" => "かぜ", "problem_diagnosis_at0077" => "2026-09-25T00:00:00",
      "problem_diagnosis_at0003" => "2026-09-25T00:00:00", "problem_diagnosis_at0030" => "", "problem_diagnosis_at0073" => "" }
  end

  it "任意項目が空欄でも保存でき、Composition には埋めた要素だけが入る" do
    post template_compositions_path(template.template_id), params: { values: real_params }

    expect(response).to have_http_status(:found) # 保存後は composition ページへ redirect
    items = Composition.last.rm_composition.dig("content", 0, "data", "items")
    expect(items.map { |item| item["archetype_node_id"] }).to eq(%w[at0002 at0077 at0003])
  end

  # R-20261125-1（案 B）: 傷病名（1..1）は、問題・診断名の ENTRY（0..1）を書くときに必須。発症日を書けば ENTRY は書かれる
  it "発症日だけ書いて必須（occurrences 下限 ≥1）の傷病名が空なら 422 で項目ラベル付きの説明を返す" do
    post template_compositions_path(template.template_id),
         params: { values: real_params.transform_values { "" }.merge("problem_diagnosis_at0077" => "2026-09-25T00:00:00") }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("プロブレム・診断名")
    expect(response.body).to include("必須項目です")
    expect(Composition.count).to eq(0)
  end

  # R-20261125-1（案 B）: 全部が空なら、項目ではなく帳票に付くメッセージで 422
  it "全部が空なら 422 で帳票に付くメッセージを返す（必須項目のエラーは出さない）" do
    post template_compositions_path(template.template_id), params: { values: real_params.transform_values { "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("値が 1 つも入力されていません")
    expect(response.body).not_to include("必須項目です")
    expect(Composition.count).to eq(0)
  end

  # skoba/anlage#35: 不正な日付は 500 ではなく 422 の説明
  it "日付の形式が不正なら 422 で説明する" do
    post template_compositions_path(template.template_id), params: { values: real_params.merge("problem_diagnosis_at0077" => "2026/03/01") }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("日付の形式")
    expect(Composition.count).to eq(0)
  end
end
