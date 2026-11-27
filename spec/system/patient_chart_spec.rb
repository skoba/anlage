require "rails_helper"

# 患者の画面（U1）を実ブラウザで通す（skoba/anlage#221、U1-6、docs/design/u1-patient-chart-plan.md、R-20261127-13）。
# 壇上の解像度 1280×720（rails_helper）。データは demo_initial。文言は docs/demo/ui-vocabulary.md の写し
RSpec.describe "患者の画面（実ブラウザ）", type: :system, js: true do
  before { Evaluation::Datasets.build("demo_initial") }

  def horizontal_scroll? = page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")

  it "DEMO-01 を開くと、プロブレムリスト・血圧のグラフ・検査結果の表が見え、横スクロールが出ない" do
    visit patient_path(OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01").ehr_id)

    expect(page).to have_css("section#problem_list tbody tr", count: 3)
    within(:xpath, "//figure[contains(@class,'series')][figcaption[starts-with(normalize-space(),'収縮期')]]") do
      expect(page).to have_css("svg.series-chart circle", count: 4)
    end
    expect(page).to have_css("section#lab_table tbody tr", count: 3)
    expect(horizontal_scroll?).to be(false)
  end

  it "検査結果の行の「グラフ」を押すと、その項目の折れ線が開く" do
    visit patient_path(OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01").ehr_id)

    expect(page).not_to have_css("figure.lab-chart svg", visible: true)
    within(:xpath, "//section[@id='lab_table']//tr[th[contains(.,'HbA1c')]]") { click_link "グラフ" }

    expect(page).to have_css("figure.lab-chart figcaption", text: "HbA1c（%）", visible: true)
    expect(page).to have_css("figure.lab-chart svg.series-chart circle", count: 3, visible: true)
  end

  it "経過の表の記録日を押すと、その記録の画面（記録の中身）に進む" do
    visit patient_path(OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01").ehr_id)

    within(:xpath, "//figure[contains(@class,'series')][figcaption[starts-with(normalize-space(),'収縮期')]]") { click_link "2026-10-15" }

    expect(page).to have_css("section#record_contents dl.record-fields dd", text: "134.0 mm[Hg]")
  end
end
