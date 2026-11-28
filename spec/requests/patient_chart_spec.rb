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
    expect(series.css("table tbody td.number").map(&:text)).to eq(%w[148 152 138 134])
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

  describe "日付と数値（skoba/anlage#250、R-20261127-20）" do
    let(:ehr) { OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-02") }
    let(:lab) { Template.active.find_by!(template_id: "LabResultReport") }

    def save_lab(name, value, units, at)
      Opt::RmCompositionCommitter.call(lab, { "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => name,
                                              "laboratory_test_analyte_at0001" => value, "laboratory_test_analyte_at0001__units" => units },
                                       ehr:, recorded_at: at)
    end

    def lab_cells(name)
      table = card("lab_table").at_css("table.data-table")
      dates = table.css("thead th").map(&:text).drop(1)
      row = table.css("tbody tr").find { _1.at_css("th").text.sub("グラフ", "").strip == name }
      dates.zip(row.css("td").map(&:text)).to_h.reject { |_date, text| text.empty? } # DEMO-02 のほかの日付の列は空
    end

    it "日本時間の朝 9 時より前（UTC では前の日）の検査は、日本時間のその日の列に出る（regression pin。既知の制限 5b）" do
      save_lab("試験項目甲", "5.5", "mmol/L", Time.utc(2026, 3, 1, 23, 30))

      show("DEMO-02")

      expect(lab_cells("試験項目甲（mmol/L）")).to eq("2026-03-02" => "5.5")
    end

    it "同じ日に 2 件あると、1 つの欄に、時刻の順で「／」で並ぶ（保存の順ではない）" do
      save_lab("試験項目乙", "6.5", "mmol/L", Time.utc(2026, 3, 2, 6, 0))
      save_lab("試験項目乙", "4.5", "mmol/L", Time.utc(2026, 3, 2, 1, 0))

      show("DEMO-02")

      expect(lab_cells("試験項目乙（mmol/L）")).to eq("2026-03-02" => "4.5／6.5")
    end

    # openehr-rails 0.15.0 から、記録した文字（`2026-03-01`・`2026-03`）がそのまま読み戻る（openehr-rails#121）。
    # Opt::RecordedTime（Time.iso8601）は日まで・月までの値を読めず nil を返すので、患者の画面は記録の開始時刻（context の start_time）の日の列に出す。
    # 0.14.1 までは gem が 00:00Z を補って読み戻し、その日（月までの値は 1 日）の列に出ていた（期待値は "2026-03-01"）。既知の制限 23
    it "イベントの時刻が日までの値の記録は、記録の開始時刻の日の列に出る（openehr-rails 0.15.0 から。既知の制限 23）" do
      Opt::RmCompositionCommitter.call(lab, { "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => "試験項目丁",
                                              "laboratory_test_analyte_at0001" => "3.5", "laboratory_test_analyte_at0001__units" => "mmol/L" },
                                       ehr:, recorded_at: Time.utc(2026, 3, 9, 1, 0)) do |canonical|
        canonical["content"].first["data"]["events"].first["time"]["value"] = "2026-03-01"
      end

      show("DEMO-02")

      expect(response).to have_http_status(:ok)
      expect(lab_cells("試験項目丁（mmol/L）")).to eq("2026-03-09" => "3.5")
    end

    it "イベントの時刻が月までの値の記録も保存でき、記録の開始時刻の日の列に出る（openehr-rails 0.15.0 から。既知の制限 23）" do
      Opt::RmCompositionCommitter.call(lab, { "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => "試験項目戊",
                                              "laboratory_test_analyte_at0001" => "4.5", "laboratory_test_analyte_at0001__units" => "mmol/L" },
                                       ehr:, recorded_at: Time.utc(2026, 3, 9, 1, 0)) do |canonical|
        canonical["content"].first["data"]["events"].first["time"]["value"] = "2026-03"
      end

      show("DEMO-02")

      expect(response).to have_http_status(:ok)
      expect(lab_cells("試験項目戊（mmol/L）")).to eq("2026-03-09" => "4.5")
    end

    it "整数の値に小数点を付けない。グラフの軸の文字も同じ" do
      save_lab("試験項目丙", "120", "mg/dL", Time.utc(2026, 3, 2, 1, 0))
      save_lab("試験項目丙", "130", "mg/dL", Time.utc(2026, 3, 9, 1, 0))

      show("DEMO-02")

      expect(lab_cells("試験項目丙（mg/dL）").values).to eq(%w[120 130])
      figure = card("lab_table").css("figure.lab-chart").find { _1.at_css("figcaption").text == "試験項目丙（mg/dL）" }
      expect(figure.css("text.series-label").map(&:text).first(2)).to eq(%w[130 120])
    end
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
    # 紹介状の傷病名（jp_referral の problem_diagnosis）は、プロブレムリストにも入る（計画書 1.4。台本 J7）
    expect(card("problem_list").css("tbody tr").map { |tr| tr.css("td").map(&:text).first(2) }).to eq([ [ "白血病", "疑い" ] ])
  end

  it "部品の並びは、プロブレムリスト → 時系列 → 検査結果 → 依頼と紹介状 → カルテ記録" do
    show("DEMO-01")

    headings = document.css("main h2").map(&:text)
    expect(headings).to eq([ "プロブレムリスト", "経過", "検査結果", "カルテ記録" ])
  end
end
