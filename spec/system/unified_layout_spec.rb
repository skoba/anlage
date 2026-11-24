require "rails_helper"

# skoba/anlage#95（M3 の W1・W2、docs/design/m3-plan.md）: 左ナビと作業面の統合レイアウト。
# 壇上の解像度 1280×720（rails_helper）で、ナビと作業面が横に並び、横スクロールが出ない。
# engine の画面（AQL 照会）も同じ layout に入り、ナビで行き来できる。
RSpec.describe "統合レイアウト（実ブラウザ）", type: :system, js: true do
  before do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).save!
  end

  def rect(selector)
    page.evaluate_script("(() => { const r = document.querySelector('#{selector}').getBoundingClientRect(); return [r.left, r.right, r.top]; })()")
  end

  def horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  end

  it "ナビが左、作業面が右に並び、横スクロールが出ない（テンプレート・カルテ記録一覧・パスカード検索・AQL 照会）" do
    [ templates_path, compositions_path, pathcards_search_path, "/openehr/query" ].each do |path|
      visit path

      _nav_left, nav_right, nav_top = rect("nav#app_nav")
      main_left, _main_right, main_top = rect("main#workspace")
      expect(nav_right).to be <= main_left, "#{path}: ナビが作業面の左にある"
      expect((nav_top - main_top).abs).to be < 1, "#{path}: ナビと作業面の上端がそろう"
      expect(horizontal_scroll?).to be(false), "#{path}: 横スクロールが出ない"
    end
  end

  it "AQL 照会からナビでテンプレートに戻れる" do
    visit templates_path
    within("nav#app_nav") { click_link "AQL 照会" }
    expect(page).to have_current_path("/openehr/query")

    within("nav#app_nav") { click_link "テンプレート" }

    expect(page).to have_current_path("/templates")
    expect(page).to have_css("h1", text: "テンプレートの取り込み")
  end
end
