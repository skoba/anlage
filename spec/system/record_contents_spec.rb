require "rails_helper"

# 記録の画面の、記録の中身（skoba/anlage#191、R-20261127-1 の 1、docs/design/m3-plan.md 9.1）を実ブラウザで通す。
# 記録を開くと値が見え、「修正」に進むと同じ値が入った帳票になる。データは demo_initial（rake demo:reset の初期状態）。
# 文言は docs/demo/ui-vocabulary.md の写し
RSpec.describe "記録の中身（実ブラウザ）", type: :system, js: true do
  before { Evaluation::Datasets.build("demo_initial") }

  it "DEMO-01 のいちばん上の CardiologyEncounter を開くと、血圧の値が見え、修正の帳票に同じ値が入っている" do
    patient = OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01")
    visit patient_path(patient.ehr_id)
    click_link "CardiologyEncounter — 記録日 2026-10-15"

    within("section#record_contents") do
      expect(page).to have_css("h2", text: "記録の中身")
      expect(page).to have_css("fieldset.record-group legend", text: "血圧")
      expect(page).to have_css("dl.record-fields dt", text: "収縮期")
      expect(page).to have_css("dl.record-fields dd", text: "134.0 mm[Hg]")
    end

    click_link "修正"

    expect(page).to have_field("収縮期", with: "134.0")
  end
end
