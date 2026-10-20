require "rails_helper"

# skoba/anlage#47 変更 1（台本 2 幕「保存 → カルテ記録画面に flash と次アクション」）を
# 実ブラウザの操作列で固定する。ビューポートは壇上の設計解像度 1280×720（rails_helper、裁定 E）。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し。
RSpec.describe "デモ動線: 保存後の次アクション（実ブラウザ）", type: :system, js: true do
  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read).tap(&:save!)
  end

  def horizontally_scrollable?
    page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
  end

  it "CardiologyEncounter を保存すると flash と次アクション 4 つが出て、「もう 1 件」で同じ帳票に戻れる" do
    visit form_path(template.template_id)

    fill_in "field_blood_pressure_at0004", with: "120"
    fill_in "field_blood_pressure_at0005", with: "80"
    click_button "送信"

    expect(page).to have_css("#flash", text: "保存しました")
    expect(page).to have_css("h1", text: "カルテ記録: CardiologyEncounter")
    within("#next_actions") do
      expect(page).to have_link("同じ帳票にもう 1 件入力", href: "/forms/CardiologyEncounter")
      expect(page).to have_link("カルテ記録一覧", href: "/compositions")
      expect(page).to have_link("AQL 照会", href: "/openehr/query")
      expect(page).to have_link("FHIR プロファイル", href: "/fhir/r5/StructureDefinition/openehr-observation-blood-pressure-v2")
    end

    # 1280×720: 共通ナビは 1 行に収まり、横スクロールは出ない（canonical JSON を開いても）
    nav_rows = page.evaluate_script("[...document.querySelectorAll('#app_nav a')].map(a => a.offsetTop)").uniq
    expect(nav_rows.size).to eq(1)
    expect(horizontally_scrollable?).to be(false)
    find("summary", text: "canonical JSON").click
    expect(page).to have_content("COMPOSITION")
    expect(horizontally_scrollable?).to be(false)

    click_link "同じ帳票にもう 1 件入力"

    expect(page).to have_current_path("/forms/CardiologyEncounter")
    expect(page).to have_field("field_blood_pressure_at0004", with: "")
    expect(Composition.count).to eq(1)
  end
end
