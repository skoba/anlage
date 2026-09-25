require "rails_helper"

# skoba/anlage#36: builder が扱えない形のテンプレートは閲覧専用＋「保存は未対応」の明示。
# 500 を壇上で出さない。
RSpec.describe "preview_only のフォーム（#36）", type: :request do
  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).tap(&:save!) }

  it "GET /forms/jp_referral は閲覧専用（入力 disabled・送信ボタン無し）で、保存未対応と理由を明示する" do
    get "/forms/jp_referral"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("保存は未対応")
    expect(response.body).to include("#30")
    expect(response.body).not_to include("<button type=\"submit\">送信</button>")
    expect(response.body).to match(/<input[^>]*name="values\[problem_diagnosis_at0002\]"[^>]*disabled/)
  end

  it "POST /compositions/jp_referral は 422 で同じ説明を返し、500 にならない" do
    post template_compositions_path("jp_referral"), params: { values: { "problem_diagnosis_at0002" => "かぜ" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("保存は未対応")
    expect(Composition.count).to eq(0)
  end
end
