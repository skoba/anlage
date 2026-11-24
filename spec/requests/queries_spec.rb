require "rails_helper"

# クエリビルダーの画面（docs/design/s2-query-builder-plan.md 6.4）。状態はすべて URL のパラメータ。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し。データは demo_initial（rake demo:reset の初期状態）、
# カードの参照（<template_id>|<path>）は実物の path。
RSpec.describe "クエリビルダー", type: :request do
  QB_BP_PATH = "/content[openEHR-EHR-OBSERVATION.blood_pressure.v2]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value".freeze
  QB_PD_ROOT = "/content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]".freeze
  QB_SYSTOLIC = "CardiologyEncounter|#{QB_BP_PATH}".freeze
  QB_DIAGNOSIS = "ProblemList|#{QB_PD_ROOT}/data[at0001]/items[at0002]/value".freeze
  QB_CERTAINTY = "ProblemList|#{QB_PD_ROOT}/data[at0001]/items[at0073]/value".freeze
  QB_ONSET = "ProblemList|#{QB_PD_ROOT}/data[at0001]/items[at0077]/value".freeze

  before { Evaluation::Datasets.build("demo_initial") }

  def doc = Nokogiri::HTML(response.body)
  def texts(selector) = doc.css(selector).map { _1.text.strip.squish }

  it "見出しと検索の入力が出て、項目を選ぶ前は AQL を出さない" do
    get "/queries/new"

    expect(response).to have_http_status(:ok)
    expect(texts("main#workspace > h1")).to eq([ "クエリビルダー" ])
    expect(doc.at_css("label[for=q]").text.strip).to eq("探したい項目")
    expect(doc.at_css("input[type=submit][name=search]")["value"]).to eq("検索")
    expect(texts("#query_columns p")).to eq([ "表示する項目を選ぶと、AQL が組まれます。" ])
    expect(doc.at_css("#query_aql")).to be_nil
  end

  it "検索するとカードが出て、カードごとに「表示する項目に足す」「条件に足す」のボタンがある" do
    get "/queries/new", params: { q: "収縮期" }

    card = doc.css("#query_candidates .pathcard").find { _1.at_css("h2").text.strip == "収縮期" }
    expect(card.text).to include("CardiologyEncounter", "at0004")
    expect(card.css("button").map { [ _1["name"], _1["value"], _1.text.strip ] })
      .to eq([ [ "add_column", QB_SYSTOLIC, "表示する項目に足す" ], [ "add_condition", QB_SYSTOLIC, "条件に足す" ] ])
  end

  it "項目を足すと「表示する項目」に並び、AQL と検査の結果（指摘なし）が出る。実行はまだしない" do
    get "/queries/new", params: { add_column: QB_SYSTOLIC }

    expect(texts("#query_columns li .card-label")).to eq([ "収縮期（CardiologyEncounter）" ])
    expect(doc.css("#query_columns input[type=hidden][name='columns[]']").map { _1["value"] }).to eq([ QB_SYSTOLIC ])
    expect(doc.at_css("#query_aql pre").text).to eq(<<~AQL.chomp)
      SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude
      FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
    AQL
    expect(texts("#query_lint p")).to eq([ "指摘はありません。" ])
    expect(doc.at_css("#query_result")).to be_nil
    expect(doc.at_css("input[type=submit][name=run]")["value"]).to eq("実行")
  end

  it "条件の入力は種類で変わる: 数値は演算子と値、値集合はコードのチェック（表示つき）、日付は範囲、文字列は一致・含むと値" do
    get "/queries/new", params: { columns: [ QB_DIAGNOSIS ], conditions: { "0" => { card: QB_SYSTOLIC }, "1" => { card: QB_CERTAINTY },
                                                                       "2" => { card: QB_ONSET }, "3" => { card: QB_DIAGNOSIS } } }

    number, code, date, text = doc.css("#query_conditions li")
    expect(number.css("select[name='conditions[0][operator]'] option").map { _1["value"] }).to eq(%w[> >= < <= =])
    expect(number.at_css("input[name='conditions[0][value]']")).to be_present
    expect(code.css("input[type=checkbox][name='conditions[1][values][]']").map { _1["value"] }).to eq(%w[at0074 at0075 at0076])
    expect(code.css("label").map { _1.text.strip }).to eq(%w[疑い 推定 確定])
    expect(date.css("input").map { _1["name"] }).to include("conditions[2][from]", "conditions[2][to]")
    expect(text.css("select[name='conditions[3][operator]'] option").map { [ _1["value"], _1.text.strip ] }).to eq([ [ "=", "一致" ], [ "CONTAINS", "含む" ] ])
    expect(text.at_css("input[name='conditions[3][value]']")).to be_present
  end

  it "実行: 収縮期 > 110 で 1 行（120.0）。見出しはカードの名前" do
    get "/queries/new", params: { columns: [ QB_SYSTOLIC ], conditions: { "0" => { card: QB_SYSTOLIC, operator: ">", value: "110" } }, run: "実行" }

    expect(doc.at_css("#query_aql pre").text).to end_with("/items[at0004]/value/magnitude > 110")
    expect(texts("#query_result p")).to eq([ "1 行" ])
    expect(texts("#query_result th")).to eq([ "収縮期" ])
    expect(texts("#query_result td")).to eq([ "120.0" ])
  end

  it "実行: 診断確度のコード at0074（疑い）を選び、文書名も表示すると、ProblemList の 2 行" do
    get "/queries/new", params: { columns: [ QB_DIAGNOSIS ], composition_name: "1",
                                  conditions: { "0" => { card: QB_CERTAINTY, values: [ "at0074" ] } }, run: "実行" }

    expect(doc.at_css("#query_aql pre").text).to include('value/defining_code/code_string MATCHES {"at0074"}')
    expect(texts("#query_result th")).to eq([ "文書名", "プロブレム・診断名" ])
    expect(doc.css("#query_result tbody tr").map { |row| row.css("td").map { _1.text.strip } })
      .to match_array([ [ "ProblemList", "高血圧症" ], [ "ProblemList", "2型糖尿病" ] ])
  end

  it "該当が無ければ「該当する記録はありません。」" do
    get "/queries/new", params: { columns: [ QB_SYSTOLIC ], conditions: { "0" => { card: QB_SYSTOLIC, operator: ">", value: "300" } }, run: "実行" }

    expect(texts("#query_result p")).to eq([ "該当する記録はありません。" ])
  end

  it "組めない選択（数値でない値、ENTRY が 2 つ）は実行せず、理由を出す" do
    get "/queries/new", params: { columns: [ QB_SYSTOLIC ], conditions: { "0" => { card: QB_SYSTOLIC, operator: ">", value: "高い" } }, run: "実行" }
    expect(texts("#query_error")).to eq([ "実行しませんでした: 収縮期 の値 \"高い\" は数値ではない" ])
    expect(doc.at_css("#query_result")).to be_nil

    get "/queries/new", params: { columns: [ QB_SYSTOLIC, QB_DIAGNOSIS ] }
    expect(texts("#query_error").first).to start_with("実行しませんでした: 1 つのクエリで使える ENTRY のアーキタイプは 1 つ")
  end

  it "外す: 項目と条件をボタンで外せる。条件に入れた値はほかの操作でも残る" do
    state = { columns: [ QB_SYSTOLIC, QB_DIAGNOSIS ], conditions: { "0" => { card: QB_SYSTOLIC, operator: ">=", value: "110" }, "1" => { card: QB_CERTAINTY, values: [ "at0075" ] } } }

    get "/queries/new", params: state.merge(remove_column: QB_DIAGNOSIS)
    expect(texts("#query_columns li .card-label")).to eq([ "収縮期（CardiologyEncounter）" ])
    expect(doc.at_css("select[name='conditions[0][operator]'] option[selected]")["value"]).to eq(">=")
    expect(doc.at_css("input[name='conditions[0][value]']")["value"]).to eq("110")
    expect(doc.css("input[name='conditions[1][values][]'][checked]").map { _1["value"] }).to eq([ "at0075" ])

    get "/queries/new", params: state.merge(remove_condition: "0")
    expect(texts("#query_conditions li .card-label")).to eq([ "診断確度（ProblemList）" ])
    expect(doc.css("input[name='conditions[0][values][]'][checked]").map { _1["value"] }).to eq([ "at0075" ])
  end

  it "active のカードに無い参照は捨てて、その旨を出す" do
    get "/queries/new", params: { columns: [ QB_SYSTOLIC, "Nowhere|/content[x]/value" ] }

    expect(texts("#query_columns li .card-label")).to eq([ "収縮期（CardiologyEncounter）" ])
    expect(texts("#query_dropped")).to eq([ "いまのテンプレートに無い項目を 1 件外しました。" ])
  end

  it "URL に AQL を渡しても実行しない（実行するのはビルダーが組んだ AQL だけ）" do
    get "/queries/new", params: { aql: "SELECT c/name/value FROM EHR e CONTAINS COMPOSITION c", run: "実行" }

    expect(doc.at_css("#query_aql")).to be_nil
    expect(doc.at_css("#query_result")).to be_nil
  end

  it "共通ナビに「クエリビルダー」があり、この画面で印が付く" do
    get "/queries/new"

    nav = doc.css("nav#app_nav a").map { [ _1.text.strip, _1["href"], _1["aria-current"] ] }
    expect(nav).to include([ "クエリビルダー", "/queries/new", "page" ])
    expect(nav.map(&:first)).to eq(%w[テンプレート カルテ記録一覧 パスカード検索 クエリビルダー] + [ "AQL 照会" ])
  end
end
