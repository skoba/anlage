require "rails_helper"

# 台本「検索」と 1' 閲覧専用（skoba/anlage#47 6 節）: 第 1 幕で登録した jp_referral を、
# パスカード検索で臨床の言葉（「既往歴」「傷病名」）から引き、カードから帳票へ移る。
# jp_referral の帳票は保存未対応（#30）なので閲覧専用で、保存ボタンが出ない。
# 検索結果は実測（docs/reports/demo-integration-log.md R12）。文言は docs/demo/ui-vocabulary.md の写し。
RSpec.describe "デモ動線: パスカード検索から帳票へ（実ブラウザ）", type: :system, js: true do
  before do
    template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read)
    template.pathcards = Opt::PathcardExtractor.call(template).cards
    template.save!
  end

  it "「既往歴」「傷病名」で jp_referral のカードが出て、「帳票に入力」で閲覧専用の帳票が開く" do
    visit pathcards_search_path

    fill_in "探したい項目", with: "既往歴"
    click_button "検索"
    expect(page).to have_css(".pathcard h2", text: "病歴の記述")

    fill_in "探したい項目", with: "傷病名"
    click_button "検索"
    card = find(".pathcard", text: "プロブレム・診断の名称")
    expect(card).to have_content("jp_referral")
    expect(card).to have_content("at0002")

    card.click_link "帳票に入力"

    expect(page).to have_current_path("/forms/jp_referral")
    expect(page).to have_content("保存は未対応（#30）")
    expect(page).not_to have_button("保存")
  end
end
