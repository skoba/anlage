require "rails_helper"

# M2 の出口（docs/design/m2-plan.md の I、R-20261124-20）: 紹介状（jp_referral）を実ブラウザの帳票から入力して保存し、
# 「紹介先医療機関」の name 述語の AQL で引ける。壇上と同じ操作列（入力欄の id、ボタンの文言）で固定する。
# 実物 fixture: jp_referral.opt v0.2。値は作例（臨床文書ではない）。
RSpec.describe "M2 の出口: 紹介状を帳票から入力して保存し、紹介先医療機関で引ける（実ブラウザ）", type: :system, js: true do
  before { select_patient_in_browser } # skoba/anlage#161: 記録は、患者を選んでから保存する（spec/support/patient_selection.rb）

  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).tap(&:save!)
  end

  it "紹介元・紹介先・傷病名を入力して保存し、name 述語の AQL で紹介先と傷病名が 1 行で引ける" do
    visit form_path(template.template_id)

    within(:xpath, "//fieldset[legend[normalize-space()='サービス依頼']]") do
      fill_in "field_service_request_at0121", with: "精査"
    end
    within(:xpath, "//fieldset[legend[normalize-space()='紹介元医療機関']]") do
      fill_in "field_organisation_at0001", with: "A診療所"
    end
    within(:xpath, "//fieldset[legend[normalize-space()='紹介先医療機関']]") do
      fill_in "field_organisation_at0001_2", with: "X病院"
    end
    within(:xpath, "//fieldset[legend[normalize-space()='傷病名']]") do
      fill_in "field_problem_diagnosis_at0002", with: "2型糖尿病"
    end
    click_button "保存"

    expect(page).to have_css("#flash", text: "保存しました")
    expect(page).to have_css("h1", text: "カルテ記録: jp_referral")
    expect(Composition.count).to eq(1)

    result = OpenehrRails::Aql::Executor.execute(<<~AQL)
      SELECT i/protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']/items[at0001]/value/value AS receiver,
             ev/data[at0001]/items[at0002]/value/value AS diagnosis
      FROM EHR e CONTAINS COMPOSITION c[openEHR-EHR-COMPOSITION.request.v1]
           CONTAINS (INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
                     AND EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1])
    AQL

    expect(result.rows).to eq([ [ "X病院", "2型糖尿病" ] ])
  end
end
