require "rails_helper"

# 組み込みの定義（docs/design/definition-registration-plan.md 3 節、skoba/anlage#281）。テンプレートに依らず検査を通る
RSpec.describe "組み込みの定義（config/definitions/builtin）" do
  it "テンプレートが 1 つも無くても、検査を通る（案も無い）" do
    expect(Definitions::Builtin.report.problems).to be_empty
  end

  it "患者の画面は、U1 の並び: プロブレムリスト → 経過 → 検査結果 → 依頼と紹介状 → 記録の一覧。どれも from: { auto: true }" do
    screen = Definitions::Builtin.report.screens.sole

    expect(screen.data["sections"].map { _1.values_at("id", "component") })
      .to eq([ %w[problem_list problem_list], %w[time_series time_series], %w[lab_table lab_table], %w[orders records], %w[records records] ])
    expect(screen.data["sections"].map { _1.dig("from", "auto") }).to all(be(true))
  end
end
