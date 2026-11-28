require "rails_helper"

# 定義の組のボタンから帳票を開き、保存のあと then の画面に進む（実ブラウザ。skoba/anlage#294、
# docs/design/definition-registration-plan.md 6 節・7 節の見せ方、R-20261128-7）。組は spec/fixtures/definitions/clinic
RSpec.describe "定義の組のボタンから帳票を保存して、then の画面に進む（実ブラウザ）", type: :system, js: true do
  around do |example|
    original = ENV["ANLAGE_DEFINITION_BUNDLE"]
    ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
    example.run
  ensure
    original ? ENV["ANLAGE_DEFINITION_BUNDLE"] = original : ENV.delete("ANLAGE_DEFINITION_BUNDLE")
  end

  before do
    Evaluation::Datasets.build("demo_initial")
    DefinitionBundle.register(Definitions::Files.read(Rails.root.join("spec/fixtures/definitions/clinic")), registered_by: "rake").bundle.activate!
  end

  it "患者の画面 → 検査結果を入力 → 保存して患者の画面へ → 保存した値が、動いている組の患者の画面の検査結果に出る" do
    ehr = select_patient_in_browser("DEMO-01")

    click_link "検査結果を入力"
    expect(page).to have_css("[data-definition-screen='clinic_spec 0.1.0 lab_entry']")
    click_link "保存して患者の画面へ"

    fill_in "field_laboratory_test_result_at0005", with: "血液検査"
    fill_in "field_laboratory_test_analyte_at0024", with: "試験項目甲"
    fill_in "field_laboratory_test_analyte_at0001", with: "3.5"
    fill_in "field_laboratory_test_analyte_at0001__units", with: "mmol/L"
    click_button "保存"

    expect(page).to have_css("#flash", text: "保存しました")
    expect(page).to have_css("[data-definition-screen='clinic_spec 0.1.0 patient_chart']")
    expect(page).to have_current_path(patient_path(ehr.ehr_id, screen: "patient_chart"))
    expect(page).to have_css("section[data-definition-section='labs'] th", text: "試験項目甲（mmol/L）")
  end
end
