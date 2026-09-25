require "rails_helper"

# skoba/anlage#34（解決形 (a) bug）: 実ブラウザで任意項目を空欄のまま送信すると
# CompositionBuilder#dv_date_time が nil.iso8601 で 500。空欄の要素は Composition に
# 含めず、OPT の occurrences 下限 ≥1 の要素が空なら 422 で説明する。
RSpec.describe "空欄の任意項目を含む Composition の保存（#34）", type: :request do
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

  it "必須（occurrences 下限 ≥1）の傷病名が空なら 422 で項目ラベル付きの説明を返す" do
    post template_compositions_path(template.template_id), params: { values: real_params.merge("problem_diagnosis_at0002" => "") }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("プロブレム・診断名")
    expect(response.body).to include("必須項目です")
    expect(Composition.count).to eq(0)
  end
end
