require "rails_helper"

# 検査器の読み元（docs/design/definition-registration-plan.md 1 節、skoba/anlage#277）。登録した組は表に「path → 文字」で持つので、
# ディレクトリと同じ検査を、対応表でもできる
RSpec.describe "Definitions::Linter の読み元" do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  let(:dir) { Rails.root.join("spec/fixtures/definitions/clinic") }

  it "ディレクトリの組を、path → 文字の対応表に読む（目録と、screens・logic の YAML）" do
    files = Definitions::Files.read(dir)

    expect(files.keys).to eq(%w[bundle.yml logic/bmi_rules.yml screens/lab_entry.yml screens/patient_chart.yml])
    expect(files["bundle.yml"]).to eq(dir.join("bundle.yml").read)
  end

  it "対応表の検査は、ディレクトリの検査と同じ結果" do
    from_files = Definitions::Linter.check(Definitions::Files.read(dir))

    expect(from_files.problems.map(&:to_h)).to eq(Definitions::Linter.call(dir).problems.map(&:to_h))
    expect(from_files.screens.map(&:id)).to eq(%w[patient_chart lab_entry])
  end

  it "対応表に無い画面は、ディレクトリのときと同じく D3（ファイルが無い）" do
    files = Definitions::Files.read(dir).except("screens/lab_entry.yml")

    expect(Definitions::Linter.check(files).problems.find { _1.code == "D3" }.message).to eq("定義のファイル screens/lab_entry.yml が無い")
  end
end
