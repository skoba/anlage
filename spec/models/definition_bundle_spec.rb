require "rails_helper"

# 定義の組の登録と版（docs/design/definition-registration-plan.md 1 節・1.1 節、skoba/anlage#277、R-20261128-7）。
# 1 行 = 1 つの組の 1 つの版。組は spec/fixtures/definitions/clinic（初期データのテンプレートの field だけを引く）
RSpec.describe DefinitionBundle do
  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  let(:files) { Definitions::Files.read(Rails.root.join("spec/fixtures/definitions/clinic")) }

  def with_version(files, version) = files.merge("bundle.yml" => files["bundle.yml"].sub(/^version: .*$/, "version: #{version}"))

  describe ".register" do
    it "検査を通った組は、下書き（draft）として足す。組の id・版・中身・checksum・検査の結果を持つ" do
      result = described_class.register(files, registered_by: "rake（operator）")

      expect(result).to be_registered
      expect(result.bundle).to have_attributes(bundle_id: "clinic_spec", version: "0.1.0", status: "draft", files:,
                                               registered_by: "rake（operator）")
      expect(result.bundle.checksum).to match(/\A\h{64}\z/)
      expect(result.bundle.lint_report.map { _1["code"] }).to eq(%w[D8]) # レビュー者の無いロジックは案（警告）
    end

    it "エラーのある組は登録できず、エラーの文が返る" do
      broken = files.merge("screens/lab_entry.yml" => files["screens/lab_entry.yml"].sub("LabResultReport", "NoSuchTemplate"))

      result = described_class.register(broken, registered_by: "rake")

      expect(result).not_to be_registered
      expect(result.errors.map(&:code)).to include("D3")
      expect(described_class.count).to eq(0)
    end

    it "同じ組・版で中身の違うものは断る（版を上げる）" do
      described_class.register(files, registered_by: "rake")
      changed = files.merge("screens/patient_chart.yml" => files["screens/patient_chart.yml"].sub("title: 患者の画面", "title: 患者の画面（改）"))

      result = described_class.register(changed, registered_by: "rake")

      expect(result).not_to be_registered
      expect(result.message).to eq("組 clinic_spec の版 0.1.0 は、別の中身で登録済み。bundle.yml の version を上げる")
    end

    it "同じ中身は「登録済み」で、行を足さない" do
      first = described_class.register(files, registered_by: "rake").bundle

      result = described_class.register(files, registered_by: "rake")

      expect(result).not_to be_registered
      expect(result.bundle).to eq(first)
      expect(result.message).to eq("組 clinic_spec の版 0.1.0 は登録済み")
      expect(described_class.count).to eq(1)
    end
  end

  describe "#activate!" do
    it "下書きを active にし、同じ組の前の active を superseded にする" do
      old = described_class.register(files, registered_by: "rake").bundle.tap(&:activate!)
      new = described_class.register(with_version(files, "0.2.0"), registered_by: "rake").bundle

      new.activate!

      expect([ old.reload.status, new.reload.status ]).to eq(%w[superseded active])
    end

    it "動かす直前に、いまのテンプレートで検査し直す。通らなければ動かさない" do
      bundle = described_class.register(files, registered_by: "rake").bundle
      Template.find_by!(template_id: "LabResultReport").destroy!

      expect { bundle.activate! }.to raise_error(DefinitionBundle::LintFailed, /D3/)
      expect(bundle.reload.status).to eq("draft")
    end
  end

  describe ".restore!" do
    it "前の版の中身で新しい版を足して動かす。版は最新のパッチを 1 つ上げ、履歴は消えない" do
      old = described_class.register(files, registered_by: "rake").bundle.tap(&:activate!)
      described_class.register(with_version(files, "0.2.0"), registered_by: "rake").bundle.activate!

      restored = described_class.restore!("clinic_spec", "0.1.0", registered_by: "rake（operator）")

      expect(restored).to have_attributes(version: "0.2.1", status: "active", restored_from: "0.1.0", registered_by: "rake（operator）")
      expect(described_class.where(bundle_id: "clinic_spec").order(:id).pluck(:version, :status))
        .to eq([ %w[0.1.0 superseded], %w[0.2.0 superseded], %w[0.2.1 active] ])
      expect(restored.files.except("bundle.yml")).to eq(old.files.except("bundle.yml"))
    end

    it "bundle.yml は version: の 1 行だけを替える" do
      described_class.register(files, registered_by: "rake").bundle.activate!

      restored = described_class.restore!("clinic_spec", "0.1.0", registered_by: "rake")

      before_lines = files["bundle.yml"].lines
      after_lines = restored.files["bundle.yml"].lines
      changed = before_lines.each_index.reject { before_lines[_1] == after_lines[_1] }
      expect(after_lines.size).to eq(before_lines.size)
      expect(changed.map { after_lines[_1] }).to eq([ "version: 0.1.1\n" ])
    end

    it "替えたあとの組が検査を通らなければ、足さない（テンプレートが消えたなど）" do
      described_class.register(files, registered_by: "rake").bundle.activate!
      Template.find_by!(template_id: "LabResultReport").destroy!

      expect { described_class.restore!("clinic_spec", "0.1.0", registered_by: "rake") }.to raise_error(DefinitionBundle::LintFailed, /D3/)
      expect(described_class.count).to eq(1)
    end
  end

  it "active は組ごとに 1 つ（表の部分索引）" do
    one = described_class.register(files, registered_by: "rake").bundle
    two = described_class.register(with_version(files, "0.2.0"), registered_by: "rake").bundle
    one.update_columns(status: "active")

    expect { two.update_columns(status: "active") }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
