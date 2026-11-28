require "rails_helper"

# 遷移の図（docs/design/definition-layer-plan.md 3.1、skoba/anlage#260）。画面が節、ボタンの open.screen が辺、
# open.form は帳票の節への辺、then.screen は帳票の節から画面への辺。組は spec/fixtures/definitions/clinic
RSpec.describe Definitions::Diagram do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  let(:report) { Definitions::Linter.call(Rails.root.join("spec/fixtures/definitions/clinic")) }
  let(:diagram) { described_class.from(report) }

  it "画面の定義から、節と辺の数が定義どおりの図が出る" do
    expect(diagram.nodes.map { [ _1.id, _1.kind, _1.label, _1.layer ] }).to eq([
      [ "screen:patient_chart", :screen, "患者の画面", 0 ],
      [ "screen:lab_entry", :screen, "検査結果の入力", 1 ],
      [ "form:LabResultReport", :form, "帳票 LabResultReport", 2 ]
    ])
    expect(diagram.edges.map { [ _1.from, _1.to, _1.label ] }).to eq([
      [ "screen:patient_chart", "screen:lab_entry", "検査結果を入力" ],
      [ "screen:lab_entry", "form:LabResultReport", "保存して患者の画面へ" ],
      [ "form:LabResultReport", "screen:patient_chart", "保存のあと" ]
    ])
  end

  it "then: { record: saved } は「保存した記録」の節へ" do
    dir = Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(Rails.root.join("spec/fixtures/definitions/clinic"), _1) }
    path = dir.join("screens/lab_entry.yml")
    path.write(path.read.sub("then: { screen: patient_chart }", "then: { record: saved }"))

    graph = described_class.from(Definitions::Linter.call(dir))

    expect(graph.edges.last.to_h).to include(from: "form:LabResultReport", to: "record:saved", label: "保存のあと")
    expect(graph.nodes.map(&:id)).to include("record:saved")
  ensure
    FileUtils.remove_entry(dir.dirname) if dir
  end

  it "Mermaid のテキスト（文書と PR に貼れる。JS は足さない）" do
    expect(diagram.to_mermaid).to eq(<<~MERMAID)
      flowchart LR
        screen_patient_chart["患者の画面"]
        screen_lab_entry["検査結果の入力"]
        form_LabResultReport[/"帳票 LabResultReport"/]
        screen_patient_chart -->|"検査結果を入力"| screen_lab_entry
        screen_lab_entry -->|"保存して患者の画面へ"| form_LabResultReport
        form_LabResultReport -->|"保存のあと"| screen_patient_chart
    MERMAID
  end

  it "検査でエラーのある組からは図を作らない" do
    broken = Definitions::Linter::Report.new(problems: [ Definitions::Problem.new(code: "D1", definition: "bundle.yml", message: "x") ], bundle: nil, screens: [], logics: [])

    expect { described_class.from(broken) }.to raise_error(ArgumentError, /エラー/)
  end
end

RSpec.describe Definitions::Diagram, "画面が 1 つでボタンが無い組" do
  it "start の節だけの図になる" do
    bundle = Definitions::Linter::Definition.new(kind: "bundle", id: "b", path: "bundle.yml", data: { "start" => { "screen" => "only" } })
    screen = Definitions::Linter::Definition.new(kind: "screen", id: "only", path: "screens/only.yml",
                                                 data: { "title" => "ひとつ", "sections" => [ { "id" => "f", "component" => "form" } ] })
    diagram = described_class.new(bundle, [ screen ])

    expect(diagram.nodes.map { [ _1.id, _1.label, _1.layer ] }).to eq([ [ "screen:only", "ひとつ", 0 ] ])
    expect(diagram.edges).to be_empty
  end
end

RSpec.describe DefinitionsHelper, type: :helper do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  it "サーバで描く SVG: 節は箱、辺は矢印の線。段の順に左から右へ" do
    diagram = Definitions::Diagram.from(Definitions::Linter.call(Rails.root.join("spec/fixtures/definitions/clinic")))
    svg = Nokogiri::HTML.fragment(helper.transition_diagram(diagram)).at_css("svg.transition-diagram")

    expect(svg["aria-label"]).to eq("遷移の図（節 3、辺 3）")
    expect(svg.css("g.diagram-node").map { [ _1["data-node"], _1.at_css("text").text ] }).to eq([
      [ "screen:patient_chart", "患者の画面" ], [ "screen:lab_entry", "検査結果の入力" ], [ "form:LabResultReport", "帳票 LabResultReport" ]
    ])
    expect(svg.css("g.diagram-edge").size).to eq(3)
    xs = svg.css("g.diagram-node rect").map { _1["x"].to_f }
    expect(xs).to eq(xs.sort)
  end
end
