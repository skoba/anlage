require "rails_helper"

# skoba/anlage#33 裁定 D: 壇上と同じ操作列を実ブラウザ（selenium_chrome_headless）で固定する。
# ProblemList のフォーム入力 → 保存 → AQL（デモクエリ 2 と同じ MATCHES）。
# 2026-08-26 以来の空 select（外部値集合のみの DV_CODED_TEXT）が POST 直叩きの
# spec/demo/ で隠れていたため、凍結受入条件に本 spec の green を加える（CLAUDE.md）。
RSpec.describe "デモ動線: ProblemList のフォーム入力→保存→AQL（実ブラウザ）", type: :system, js: true do
  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!)
  end

  # skoba/anlage#34: 壇上で全欄を埋める人はいない——任意項目（日時 3 件）は空欄のまま保存する
  # 現実の操作列で固定する
  it "傷病名を自由記載し、診断確度を選び、任意項目は空欄のまま保存した Composition を AQL で引ける" do
    visit form_path(template.template_id)

    fill_in "field_problem_diagnosis_at0002", with: "2型糖尿病"
    select "疑い", from: "field_problem_diagnosis_at0073"
    click_button "送信"

    # 保存後は composition ページ（canonical JSON 表示）へ遷移する（flash は layout に無い）
    expect(page).to have_content("COMPOSITION")
    expect(page).to have_content("2型糖尿病")
    expect(Composition.count).to eq(1)

    query = <<~AQL
      SELECT c/name/value AS composition_name,
             o/data[at0001]/items[at0002]/value/value AS diagnosis,
             o/data[at0001]/items[at0073]/value/value AS certainty
      FROM EHR e CONTAINS COMPOSITION c
           CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
      WHERE o/data[at0001]/items[at0073]/value/value MATCHES {"疑い", "推定"}
    AQL

    result = OpenehrRails::Aql::Executor.execute(query)

    expect(result.rows).to eq([ [ "ProblemList", "2型糖尿病", "疑い" ] ])
  end
end
