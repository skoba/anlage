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
