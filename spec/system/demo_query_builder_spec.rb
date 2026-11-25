require "rails_helper"

# クエリビルダー（docs/design/s2-query-builder-plan.md 6.4、R-20261124-21）を実ブラウザの操作列で通す。
# 臨床の言葉で項目を探す → 表示する項目と条件に足す → 型に応じた条件を入れる → AQL と検査を見る → 実行して行を見る。
# データは demo_initial（rake demo:reset の初期状態）。期待する行は評価 v2 のゴールド a001・a002 と同じ。文言は docs/demo/ui-vocabulary.md の写し。
RSpec.describe "クエリビルダー（実ブラウザ）", type: :system, js: true do
  before { Evaluation::Datasets.build("demo_initial") }

  def candidate(name, template)
    find("#query_candidates .pathcard", text: template, match: :first) { |card| card.has_css?("h2", text: name, exact_text: true) }
  end

  it "数値: 「収縮期」を探して項目と条件に足し、> 110 で実行すると 120.0 の 1 行が出る" do
    visit new_query_path
    within("nav#app_nav") { expect(page).to have_css("a[aria-current=page]", text: "クエリビルダー") }

    fill_in "探したい項目", with: "収縮期"
    click_button "検索"
    candidate("収縮期", "CardiologyEncounter").click_button "表示する項目に足す"
    expect(page).to have_css("#query_columns li .card-label", text: "収縮期（CardiologyEncounter）")
    expect(page).to have_css("#query_aql pre", text: "FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]")

    candidate("収縮期", "CardiologyEncounter").click_button "条件に足す"
    within("#query_conditions li") do
      select ">", from: "condition_0_operator"
      fill_in "condition_0_value", with: "110"
    end
    click_button "AQL を組む"
    expect(page).to have_css("#query_aql pre", text: "/items[at0004]/value/magnitude > 110")
    expect(page).to have_css("#query_lint p", text: "指摘はありません。")
    expect(page).not_to have_css("#query_result")

    click_button "実行"

    expect(page).to have_css("#query_result p", text: "1 行")
    expect(page).to have_css("#query_result th", text: "収縮期")
    expect(page).to have_css("#query_result td", text: "120.0")
    expect(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")).to be(false)
  end

  it "値集合: 傷病名を表示し、診断確度「疑い」にチェックして文書名つきで実行すると、ProblemList の 2 行が出る（コード値 at0074 で引く）" do
    visit new_query_path

    fill_in "探したい項目", with: "診断名"
    click_button "検索"
    candidate("プロブレム・診断名", "ProblemList").click_button "表示する項目に足す"
    expect(page).to have_css("#query_columns li", count: 1)

    fill_in "探したい項目", with: "診断確度"
    click_button "検索"
    candidate("診断確度", "ProblemList").click_button "条件に足す"
    within("#query_conditions li") { check "疑い" }
    check "文書名も表示する"
    click_button "実行"

    expect(page).to have_css("#query_aql pre", text: 'value/defining_code/code_string MATCHES {"at0074"}')
    expect(page).to have_css("#query_result p", text: "2 行")
    rows = all("#query_result tbody tr").map { |row| row.all("td").map(&:text) }
    expect(rows).to match_array([ [ "ProblemList", "高血圧症" ], [ "ProblemList", "2型糖尿病" ] ])
  end

  it "組めない値（数値でない）は実行せず、理由が出る。直して実行できる" do
    visit new_query_path
    fill_in "探したい項目", with: "収縮期"
    click_button "検索"
    candidate("収縮期", "CardiologyEncounter").click_button "表示する項目に足す"
    expect(page).to have_css("#query_columns li", count: 1)
    candidate("収縮期", "CardiologyEncounter").click_button "条件に足す"
    expect(page).to have_css("#query_conditions li", count: 1)
    fill_in "condition_0_value", with: "高い"
    click_button "実行"

    expect(page).to have_css("#query_error", text: "実行しませんでした: 収縮期 の値 \"高い\" は数値ではない")
    expect(page).not_to have_css("#query_result")

    fill_in "condition_0_value", with: "300"
    click_button "実行"
    expect(page).to have_css("#query_result p", text: "該当する記録はありません。")
  end
  # docs/design/s2-query-builder-plan.md 7.4（R-20261125-6）
  it "未記入を含む: 診断確度「確定」だけでは該当なし。「未記入を含む」にチェックすると、確度の記載が無い 1 行が出る" do
    visit new_query_path

    fill_in "探したい項目", with: "診断名"
    click_button "検索"
    candidate("プロブレム・診断名", "ProblemList").click_button "表示する項目に足す"
    expect(page).to have_css("#query_columns li", count: 1)
    fill_in "探したい項目", with: "診断確度"
    click_button "検索"
    candidate("診断確度", "ProblemList").click_button "条件に足す"
    within("#query_conditions li") { check "確定" }
    click_button "実行"
    expect(page).to have_css("#query_result p", text: "該当する記録はありません。")

    within("#query_conditions li") { check "未記入を含む" }
    click_button "実行"

    expect(page).to have_css("#query_aql pre", text: 'MATCHES {"at0076"} OR NOT EXISTS ev/data[at0001]/items[at0073]/value)')
    expect(page).to have_css("#query_lint p", text: "指摘はありません。")
    expect(page).to have_css("#query_result p", text: "1 行")
    expect(page).to have_css("#query_result td", text: "2型糖尿病")
  end

  it "範囲の外・どちらかを満たす: 収縮期が 100〜110 の外、または拡張期 >= 90 で実行すると、120／80 の 1 行が出る" do
    visit new_query_path

    fill_in "探したい項目", with: "血圧"
    click_button "検索"
    # ボタンを押すたびに画面が読み直される。次のボタンは、読み直しを待ってから押す（待たないと、古い画面のボタンを押して前の操作が消える）
    candidate("収縮期", "CardiologyEncounter").click_button "表示する項目に足す"
    expect(page).to have_css("#query_columns li", count: 1)
    candidate("拡張期", "CardiologyEncounter").click_button "表示する項目に足す"
    expect(page).to have_css("#query_columns li", count: 2)
    candidate("収縮期", "CardiologyEncounter").click_button "条件に足す"
    expect(page).to have_css("#query_conditions li", count: 1)
    candidate("拡張期", "CardiologyEncounter").click_button "条件に足す"
    expect(page).to have_css("#query_conditions li", count: 2)

    select "範囲の外", from: "condition_0_operator"
    click_button "AQL を組む"
    expect(page).to have_css("#query_error", text: "下限と上限の両方が要る")
    expect(page).to have_field("condition_0_low")
    fill_in "condition_0_low", with: "100"
    fill_in "condition_0_high", with: "110"
    select ">=", from: "condition_1_operator"
    fill_in "condition_1_value", with: "90"
    check "前の条件と「または」でつなぐ"
    click_button "実行"

    expect(page).to have_css("#query_conditions li .connector", text: "または")
    expect(page).to have_css("#query_aql pre", text: "/items[at0004]/value/magnitude > 110) OR o/data[at0001]/events[at0006]/data[at0003]/items[at0005]/value/magnitude >= 90)")
    expect(page).to have_css("#query_result p", text: "1 行")
    expect(all("#query_result tbody td").map(&:text)).to eq([ "120.0", "80.0" ])
    expect(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")).to be(false)
  end
end
