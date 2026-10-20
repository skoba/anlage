require "rails_helper"
require "rake"

Rails.application.load_tasks

# 台本 3' 幕（skoba/anlage#47、裁定 2026-10-20）: 同じ問題・診断アーキタイプを使う ProblemList と
# jp_referral が、1 本の AQL で同時に引ける（骨格契約の横串一貫性）。name 述語を使わない形
# （紹介先医療機関で引く形は上流 24 項＝openehr-ruby#60 の解消後）。出所は Composition 名で並記する
# （c/archetype_details/template_id は現行エンジンの終端ホップ外、log R10）。
# 初期状態（rake demo:reset）で 2 テンプレート・3 件、壇上でフォームから 1 件足すと 4 件。
RSpec.describe "デモクエリ 5: テンプレート横断の傷病名（demo:reset の初期状態から）", type: :request do
  CROSS_TEMPLATE_AQL = <<~AQL
    SELECT c/name/value AS composition_name,
           ev/data[at0001]/items[at0002]/value/value AS diagnosis
    FROM EHR e CONTAINS COMPOSITION c
         CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
    WHERE ev/data[at0001]/items[at0002]/value/value MATCHES {"2型糖尿病", "高血圧症"}
  AQL

  before do
    Rake::Task["demo:reset"].reenable
    Rake::Task["demo:reset"].invoke
  end

  it "初期状態で ProblemList 2 件と jp_referral 1 件（2 テンプレート・3 件）を返す" do
    rows = OpenehrRails::Aql::Executor.execute(CROSS_TEMPLATE_AQL).rows

    expect(rows).to contain_exactly([ "ProblemList", "2型糖尿病" ], [ "ProblemList", "高血圧症" ], [ "jp_referral", "2型糖尿病" ])
  end

  it "壇上でフォームから 1 件足すと 4 件になる" do
    post template_compositions_path("ProblemList"), params: {
      values: { "problem_diagnosis_at0002" => "2型糖尿病", "problem_diagnosis_at0073" => "at0074" }
    }
    expect(response).to have_http_status(:redirect)

    rows = OpenehrRails::Aql::Executor.execute(CROSS_TEMPLATE_AQL).rows

    expect(rows.size).to eq(4)
    expect(rows.count { _1 == [ "ProblemList", "2型糖尿病" ] }).to eq(2)
  end
end
