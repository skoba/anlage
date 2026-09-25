require "rails_helper"

# skoba/anlage#37・#38: 実ブラウザの操作列（LabResultReport: 検査名・分析名・数値＋単位 → 保存 → AQL）。
RSpec.describe "デモ動線: LabResultReport のフォーム入力→保存→AQL（実ブラウザ）", type: :system, js: true do
  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read).tap(&:save!) }

  it "検査名・分析名・数値と単位を入力して保存し、CLUSTER 配下の数値を AQL で比較できる" do
    visit form_path(template.template_id)

    fill_in "field_laboratory_test_result_at0005", with: "血液検査"
    fill_in "field_laboratory_test_analyte_at0024", with: "空腹時血糖"
    fill_in "field_laboratory_test_analyte_at0001", with: "98"
    fill_in "field_laboratory_test_analyte_at0001__units", with: "mg/dL"
    click_button "送信"

    expect(page).to have_content("COMPOSITION")
    expect(Composition.count).to eq(1)

    query = <<~AQL
      SELECT cl/items[at0024]/value/value AS analyte, cl/items[at0001]/value/magnitude AS result
      FROM EHR e CONTAINS COMPOSITION c
           CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]
           CONTAINS CLUSTER cl[openEHR-EHR-CLUSTER.laboratory_test_analyte.v1]
      WHERE cl/items[at0001]/value/magnitude > 50
    AQL

    expect(OpenehrRails::Aql::Executor.execute(query).rows).to eq([ [ "空腹時血糖", 98.0 ] ])
  end
end
