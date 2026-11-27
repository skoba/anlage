require "rails_helper"

# 患者の画面の部品（skoba/anlage#220、U1-3〜U1-5、docs/design/u1-patient-chart-plan.md 1.3〜1.5、R-20261127-13）。
# データは demo_initial（rake demo:reset の初期状態）。文言は docs/demo/ui-vocabulary.md の写し
RSpec.describe "患者の画面の部品", type: :request do
  before { Evaluation::Datasets.build("demo_initial") }

  def document = Nokogiri::HTML(response.body)
  def show(subject_id) = get("/patients/#{OpenehrRails::Rm::Ehr.find_by!(subject_id:).ehr_id}")
  def card(id) = document.at_css("section##{id}")

  it "プロブレムリスト: 列の見出しはテンプレートのラベル、DEMO-01 は 3 行で確度は「確定」" do
    show("DEMO-01")

    table = card("problem_list").at_css("table.data-table")
    expect(card("problem_list").at_css("h2").text).to eq("プロブレムリスト")
    expect(table.css("thead th").map(&:text)).to eq([ "プロブレム・診断名", "診断確度", "発症日時", "記録日" ])
    rows = table.css("tbody tr").map { |tr| tr.css("td").map(&:text) }
    expect(rows.map(&:first)).to contain_exactly("2型糖尿病", "糖尿病性腎症", "高血圧症")
    expect(rows.map(&:second)).to all(eq("確定"))
  end

  it "時系列: 収縮期は 4 点の折れ線（SVG）と表。単位はテンプレートから" do
    show("DEMO-01")

    series = card("time_series").css("figure.series").find { _1.at_css("figcaption").text.start_with?("収縮期") }
    expect(series.at_css("figcaption").text).to eq("収縮期（CardiologyEncounter、mm[Hg]）")
    expect(series.css("svg.series-chart circle").size).to eq(4)
    expect(series.css("table tbody td.number").map(&:text)).to eq(%w[148.0 152.0 138.0 134.0])
  end

  it "時系列: 1 点だけの系列は表だけ（SVG を描かない）" do
    show("DEMO-06")

    one_point = card("time_series").css("figure.series").find { _1.at_css("figcaption").text.start_with?("収縮期") }
    expect(one_point.at_css("svg")).to be_nil
    expect(one_point.css("table tbody td.number").size).to eq(1)
  end

  it "検査結果の時系列表: 行は分析名（単位）、列は日付。2 点以上の行だけがグラフを開ける" do
    show("DEMO-01")

    table = card("lab_table").at_css("table.data-table")
    expect(table.css("thead th").map(&:text)).to eq([ "項目", "2026-01-15", "2026-04-15", "2026-07-15" ])
    rows = table.css("tbody tr").to_h { |tr| [ tr.at_css("th").text.sub("グラフ", "").strip, tr.css("td").map(&:text) ] }
    expect(rows["HbA1c（%）"]).to eq(%w[8.1 7.6 7.2])
    expect(rows["クレアチニン（mg/dL）"]).to eq([ "1.32", "", "1.45" ])
    expect(card("lab_table").css(".lab-chart svg.series-chart").size).to eq(3)
  end

  it "検査結果の時系列表: DEMO-07 は 5 行、各 1 点なのでグラフは無い" do
    show("DEMO-07")

    expect(card("lab_table").css("tbody tr").size).to eq(5)
    expect(card("lab_table").css(".lab-chart")).to be_empty
  end

  it "依頼と紹介状: jp_referral を登録すると、DEMO-07 の紹介状が出る。未登録のときは出ない" do
    show("DEMO-07")
    expect(card("orders")).to be_nil

    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).save!
    show("DEMO-07")

    expect(card("orders").at_css("h2").text).to eq("依頼と紹介状")
    expect(card("orders").css("tbody tr").map { |tr| tr.css("td").map(&:text) }).to eq([ [ "2026-06-18", "jp_referral" ] ])
  end

  it "部品の並びは、プロブレムリスト → 時系列 → 検査結果 → 依頼と紹介状 → カルテ記録" do
    show("DEMO-01")

    headings = document.css("main h2").map(&:text)
    expect(headings).to eq([ "プロブレムリスト", "経過", "検査結果", "カルテ記録" ])
  end
end
