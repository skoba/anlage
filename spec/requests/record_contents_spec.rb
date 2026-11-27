require "rails_helper"

# 記録の画面に、記録の中身を帳票の形で出す（skoba/anlage#191、R-20261127-1 の 1、docs/design/m3-plan.md 9.1）。
# 並び・ラベル・単位・選択肢の表示はテンプレート（web_template）から取り、記録からは値だけを取る。
# 帳票に読み戻せない記録は、名前と値の表（Records::ElementList）で出す。文言は docs/demo/ui-vocabulary.md の写し
RSpec.describe "記録の画面の、記録の中身（#191）", type: :request do
  before { select_patient } # skoba/anlage#161: 記録は、患者を選んでから保存する（spec/support/patient_selection.rb）

  def document = Nokogiri::HTML(response.body)
  def contents = document.at_css("section#record_contents")

  # 入れ子の見出し（legend）と、項目の「ラベル: 値」を文書の順に
  def groups(node = contents) = node.css("fieldset.record-group > legend").map(&:text)
  def fields(node = contents) = node.css("dl.record-fields").flat_map { |dl| dl.css("dt").map(&:text).zip(dl.css("dd").map(&:text)) }

  def register(name) = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).tap(&:save!)

  def save(template, values)
    post "/compositions/#{template.template_id}", params: { values: values }
    Composition.order(:id).last
  end

  it "帳票と同じ見出しとラベルで、値のある項目を出す。選択肢はテンプレートの表示、値の無い項目は出さない" do
    problem_list = register("ProblemList")
    record = save(problem_list, "problem_diagnosis_at0002" => "高血圧症", "problem_diagnosis_at0073" => "at0076")

    get "/compositions/#{record.id}"

    expect(contents.at_css("h2").text).to eq("記録の中身")
    expect(groups).to eq([ "プロブレム・診断" ])
    expect(fields).to eq([ [ "プロブレム・診断名", "高血圧症" ], [ "診断確度", "確定" ] ])
    expect(document.at_css("details summary").text).to eq("canonical JSON")
  end

  it "数量は値と単位を出し、埋め込みの CLUSTER は入れ子の見出しの下に出す" do
    lab = register("LabResultReport")
    record = save(lab, "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => "HbA1c",
                       "laboratory_test_analyte_at0001" => "6.8", "laboratory_test_analyte_at0001__units" => "%")

    get "/compositions/#{record.id}"

    expect(groups).to eq([ "検体検査結果", "検査分析結果" ])
    outer = contents.at_css("fieldset.record-group")
    expect(outer.at_css("> dl.record-fields dt").text).to eq("検査名")
    expect(fields(outer.at_css("fieldset.record-group"))).to eq([ [ "分析名", "HbA1c" ], [ "分析結果", "6.8 %" ] ])
  end

  it "単位が 1 つに決まっている数量は、テンプレートの単位を出す（値は記録の magnitude のまま）" do
    cardiology = register("CardiologyEncounter")
    record = save(cardiology, "blood_pressure_at0004" => "134", "blood_pressure_at0005" => "82")

    get "/compositions/#{record.id}"

    expect(fields).to eq([ [ "収縮期", "134.0 mm[Hg]" ], [ "拡張期", "82.0 mm[Hg]" ] ])
  end

  it "古い版を開くと、その版の値を出す" do
    problem_list = register("ProblemList")
    first = save(problem_list, "problem_diagnosis_at0002" => "高血圧症")
    patch "/compositions/#{first.id}", params: { values: { "problem_diagnosis_at0002" => "本態性高血圧症" } }
    second = Composition.order(:id).last

    get "/compositions/#{first.id}"
    expect(fields).to eq([ [ "プロブレム・診断名", "高血圧症" ] ])

    get "/compositions/#{second.id}"
    expect(fields).to eq([ [ "プロブレム・診断名", "本態性高血圧症" ] ])
  end

  it "帳票に読み戻せない記録（jp_referral）は、注記と、名前と値の表で出す" do
    referral = register("jp_referral")
    record = save(referral, "service_request_at0121" => "精査", "organisation_at0001" => "A診療所",
                            "organisation_at0001_2" => "Y病院", "problem_diagnosis_at0002" => "慢性腎臓病")

    get "/compositions/#{record.id}"

    expect(contents.at_css("p.form-notice").text).to eq("この記録は帳票の形に読み戻せません。項目の名前と値を、記録に書いてあるとおりに出します。")
    expect(contents.css("fieldset.record-group")).to be_empty
    rows = contents.css("table.record-items tbody tr").map { |tr| tr.css("td").map(&:text) }
    expect(rows).to include([ "サービス名", "精査" ], [ "名称", "Y病院" ])
    expect(rows.map(&:last)).to include("慢性腎臓病")
  end
end
