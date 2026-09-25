require "rails_helper"

# skoba/anlage#33 pin: 外部用語束縛（referenceSetUri のみ）の傷病名は text input。
# 2026-08-26（openehr-rails 0.5.0 bump）以来の空 select を固定的に防ぐ。
RSpec.describe "フォーム描画の input_kind（#33）", type: :request do
  %w[ProblemList jp_referral].each do |name|
    it "#{name} の傷病名 at0002 は text input として描画され、select ではない" do
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!

      get "/forms/#{name}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<input[^>]*type="text"[^>]*name="values\[problem_diagnosis_at0002\]"/)
      expect(response.body).not_to match(/<select[^>]*name="values\[problem_diagnosis_at0002\]"/)
    end
  end

  it "診断確度 at0073（ローカル code_list）は引き続き select" do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).save!

    get "/forms/ProblemList"

    expect(response.body).to match(/<select[^>]*name="values\[problem_diagnosis_at0073\]"/)
  end
end
