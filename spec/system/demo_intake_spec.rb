require "rails_helper"

# 台本 1 幕（skoba/anlage#47 6 節）: 「ファイルを選択」→ jp_referral.opt → 受付表示 →
# 取り込みプレビュー（アーキタイプ検出ログ・版の並記）→ 登録 → カードがリロード無しで並ぶ。
# ドラッグ＆ドロップはブラウザ間で移植可能に台本化できないため、同じ controller action・
# 同じサーバ往復を通る hidden file input 経由（「ファイルを選択」の先）で操作する。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し。旧 opt_dropzone_spec を改名・拡張。
RSpec.describe "デモ動線: テンプレートの取り込み（実ブラウザ）", type: :system, js: true do
  let(:jp_referral_path) { Rails.root.join("spec/fixtures/opt/jp_referral.opt") }

  it "jp_referral.opt を受け付けると、受付表示・取り込みプレビュー・版の並記を経て登録できる" do
    visit templates_path
    expect(page).to have_content("No templates registered yet")
    expect(page).to have_button("ファイルを選択")

    attach_file("opt_file_input", jp_referral_path.to_s, visible: false)

    # 受付直後からファイル名と状態が出て、プレビューが開いた後は確認待ちになる
    expect(page).to have_css("#queue_status", text: "受付: jp_referral.opt")
    expect(page).to have_css("h2", text: "テンプレートの取り込み: jp_referral")
    expect(page).to have_content("archetype検出") # 解析ログの再生（フォームより先に出る）
    expect(page).to have_css("#version_label", text: "登録版 v1.0.0／テンプレート版 0.2.0")
    expect(page).to have_button("登録")
    expect(page).to have_css("#queue_status", text: "受付: jp_referral.opt（確認待ち）")

    click_button "登録"

    expect(page).to have_css("#catalog .template-card .version-label", text: "登録版 v1.0.0／テンプレート版 0.2.0")
    expect(page).not_to have_content("No templates registered yet")
    expect(page).not_to have_css("#queue_status", text: "受付")
  end

  it "同じ checksum の OPT を再び受け付けると登録済みと知らせる" do
    Template.build_from_opt_xml(jp_referral_path.read).save!
    visit templates_path

    attach_file("opt_file_input", jp_referral_path.to_s, visible: false)

    expect(page).to have_content("登録済み")
  end
end
