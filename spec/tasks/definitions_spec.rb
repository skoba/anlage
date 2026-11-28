require "rails_helper"

# rake definitions:lint（docs/design/definition-layer-plan.md 2.4、skoba/anlage#257）。AI のエージェントと CI が呼ぶ入口。
# 人が読む文（既定）と、機械が読む JSON（FORMAT=json）。エラーがあれば終了コード 1（案〔D8〕だけなら 0）
RSpec.describe "definitions:lint" do
  let(:dir) { Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(Rails.root.join("spec/fixtures/definitions/clinic"), _1) } }

  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  after do
    FileUtils.remove_entry(dir.dirname)
    ENV.delete("DIR")
    ENV.delete("FORMAT")
  end

  def run_task(dir_value, format: nil)
    ENV["DIR"] = dir_value.to_s
    format ? ENV["FORMAT"] = format : ENV.delete("FORMAT")
    Rake::Task["definitions:lint"].reenable
    Rake::Task["definitions:lint"].invoke
  end

  it "案だけの組は終了コード 0。人が読む文で、件数と D8 を出す" do
    expect { run_task(dir) }.to output(/エラー 0 件、案 1 件.*logic\/bmi_rules\.yml: reviewed_by が無い。案として扱い、保存には効かない  \[D8\]/m).to_stdout
  end

  it "エラーがあれば、候補つきの文を出して終了コード 1" do
    path = dir.join("screens/patient_chart.yml")
    path.write(path.read.sub("field: laboratory_test_analyte_at0001", "field: laboratory_test_analyte_at0002"))

    expect { run_task(dir) }
      .to output(%r{screens/patient_chart\.yml: /sections/1/from/field: "laboratory_test_analyte_at0002" は LabResultReport に無い  \[D3\]\n  候補: }).to_stdout
      .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
  end

  it "FORMAT=json は、問題の配列を JSON で出す" do
    json = JSON.parse(capture_stdout { run_task(dir, format: "json") })

    expect(json).to include("ok" => true, "problems" => [ include("code" => "D8", "definition" => "logic/bmi_rules.yml", "severity" => "draft") ])
  end

  it "DIR が無ければ、使い方を出して止まる" do
    expect { run_task("") }.to raise_error(SystemExit).and output(/DIR=/).to_stderr
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

# rake definitions:context（AI に渡す材料。skoba/anlage#259）。Markdown（既定）と JSON（FORMAT=json）
RSpec.describe "definitions:context" do
  before do
    %w[LabResultReport ProblemList].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  after { ENV.delete("FORMAT") }

  def run_task(format: nil)
    format ? ENV["FORMAT"] = format : ENV.delete("FORMAT")
    Rake::Task["definitions:context"].reenable
    Rake::Task["definitions:context"].invoke
  end

  it "Markdown: テンプレートの項目の表、部品、検査の一覧、スキーマと例の見出し" do
    expect { run_task }.to output(
      /# 定義を書くための材料.*## テンプレート.*\| laboratory_test_analyte_at0024 \| 分析名 \| DV_TEXT \|.*## 部品.*## 検査.*D3.*## スキーマ.*## 例.*bundle\.yml/m
    ).to_stdout
  end

  it "JSON: Definitions::Context と同じ中身" do
    out = StringIO.new
    original = $stdout
    $stdout = out
    run_task(format: "json")
    $stdout = original

    expect(JSON.parse(out.string).keys).to eq(%w[templates components from_rule schemas checks examples])
  end
end

# rake definitions:diagram（遷移の図の Mermaid のテキスト。skoba/anlage#260）
RSpec.describe "definitions:diagram" do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  after { ENV.delete("DIR") }

  def run_task(dir)
    ENV["DIR"] = dir.to_s
    Rake::Task["definitions:diagram"].reenable
    Rake::Task["definitions:diagram"].invoke
  end

  it "検査を通る組は、Mermaid のテキストを出す" do
    expect { run_task(Rails.root.join("spec/fixtures/definitions/clinic")) }
      .to output(/\Aflowchart LR\n  screen_patient_chart\["患者の画面"\]\n/).to_stdout
  end

  it "エラーのある組は、検査の結果を出して終了コード 1（図は出さない）" do
    dir = Pathname(Dir.mktmpdir)
    dir.join("bundle.yml").write("bundle: [\n")

    expect { run_task(dir) }.to output(/\[D1\]/).to_stdout.and raise_error(SystemExit) { expect(_1.status).to eq(1) }
  ensure
    FileUtils.remove_entry(dir)
  end
end
