require "rails_helper"
require "rake"
require "tmpdir"
require "yaml"

Rails.application.load_tasks

# fsh-plan v1 の出力提供形（`docs/design/fsh-plan.md`「出力の提供形」裁定・
# 判断4）。FSH 本文は gem の `OpenehrRails::Fhir::FshGenerator` の出力そのもの
# で、Anlage 側では一切再導出しない（「二重導出禁止」、同 plan Step 2）。
#
# テストTODO:
# - [x] active テンプレートごとに SUSHI プロジェクト（sushi-config.yaml + input/fsh/*.fsh）を出力する
# - [x] FSH 本文は FshGenerator#to_fsh_files と一致する
# - [x] superseded テンプレートは出力しない
# - [x] fsh:verify は各プロジェクトを sushi に通し、Errors/Warnings 件数を報告する
# - [x] fsh:verify は sushi が無ければ中断して理由を出す
# - [x] openehr-rails 0.7.0: ProblemList の FSH から Condition.component が消え、skipped が空（regression pin）
RSpec.describe "fsh:export / fsh:verify" do
  def run_task(name, *args)
    Rake::Task[name].reenable
    Rake::Task[name].invoke(*args)
  end

  around do |example|
    Dir.mktmpdir("anlage-fsh") do |dir|
      @output_dir = Pathname(dir)
      example.run
    end
  end

  let(:bmi_xml) { Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read }
  let(:problem_list_xml) { Rails.root.join("spec/fixtures/opt/ProblemList.opt").read }

  describe "fsh:export" do
    let!(:template) { Template.build_from_opt_xml(bmi_xml).tap(&:save!) }

    it "active テンプレートごとに SUSHI プロジェクト（sushi-config.yaml + input/fsh/*.fsh）を出力する" do
      run_task("fsh:export", @output_dir.to_s)

      project_dirs = @output_dir.children.select(&:directory?)
      expect(project_dirs.size).to eq(1)

      config = YAML.safe_load(project_dirs.first.join("sushi-config.yaml").read)
      expect(config).to include("fhirVersion" => "5.0.0", "FSHOnly" => true)

      expected = OpenehrRails::Fhir::FshGenerator.new(Opt::SafeParser.parse(bmi_xml)).to_fsh_files
      fsh_dir = project_dirs.first.join("input/fsh")
      expect(fsh_dir.glob("*.fsh").map { |path| path.basename(".fsh").to_s }).to match_array(expected.keys)
      expected.each do |profile_id, fsh|
        expect(fsh_dir.join("#{profile_id}.fsh").read).to eq(fsh)
      end
    end

    it "superseded テンプレートは出力しない" do
      Template.build_from_opt_xml(problem_list_xml).tap(&:save!).supersede!

      run_task("fsh:export", @output_dir.to_s)

      project_dirs = @output_dir.children.select(&:directory?)
      expect(project_dirs.size).to eq(1)
      expect(project_dirs.first.join("input/fsh").glob("*.fsh").map { |path| path.basename.to_s })
        .to all(start_with("openehr-observation-"))
    end
  end

  # regression pin（解決形 (c)）: openehr-rails 0.7.0 で EVALUATION の
  # Condition.component スライスが撤去され（rails #33）、ProblemList の Sushi
  # エラーが 29 → 0 になったことを、sushi 無しで検査できる形に固定する
  # （`docs/reports/fsh-log.md` R7 の 29 件は全て `No element found at path
  # component`。R8 で 0 Errors を実測）。0.7.0 bump 時点で既に成立している
  # 性質の固定であり、Red は作れない。
  describe "openehr-rails 0.7.0 の FSH（regression pin）" do
    let(:fixture_paths) { Rails.root.glob("spec/fixtures/opt/*.opt").sort }

    it "ProblemList の FSH に Condition.component 制約が含まれない" do
      fsh_files = OpenehrRails::Fhir::FshGenerator.new(Opt::SafeParser.parse(problem_list_xml)).to_fsh_files

      expect(fsh_files.keys).to eq([ "openehr-evaluation-problem-diagnosis-v1" ])
      expect(fsh_files.values.join).not_to include("component")
      expect(fsh_files.values.join).to include("* category contains ckm 1..1")
    end

    it "spec fixture 5 件とも skip-and-report の対象（skipped）が空である" do
      skipped = fixture_paths.to_h do |path|
        generator = OpenehrRails::Fhir::FshGenerator.new(Opt::SafeParser.parse(path.read))
        generator.to_fsh_files
        [ path.basename.to_s, generator.skipped ]
      end

      expect(skipped.keys.size).to eq(5)
      expect(skipped.values).to all(be_empty)
    end
  end

  describe "fsh:verify" do
    # sushi 本体（Node）は Anlage の依存に含めない（fsh-plan 判断3: ローカル・
    # 手動実行まで）。ここでは PATH 先頭に置いたスタブ実行ファイルで、
    # 出力の要約行（`N Errors  M Warnings`）を読み取る契約だけを固定する。
    def with_stub_sushi(script)
      Dir.mktmpdir("stub-sushi") do |bin_dir|
        stub = Pathname(bin_dir).join("sushi")
        stub.write(script)
        stub.chmod(0o755)
        original_path = ENV["PATH"]
        ENV["PATH"] = "#{bin_dir}#{File::PATH_SEPARATOR}#{original_path}"
        yield
      ensure
        ENV["PATH"] = original_path
      end
    end

    before do
      @output_dir.join("bmi-calculation/input/fsh").mkpath
      @output_dir.join("bmi-calculation/sushi-config.yaml").write("fhirVersion: 5.0.0\n")
    end

    it "各プロジェクトを sushi に通し、Errors/Warnings 件数を報告する" do
      script = <<~SH
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "SUSHI v0.0.0-stub"; exit 0; fi
        echo "╚════ 2 Errors  1 Warning ════╝"
        exit 1
      SH

      output = with_stub_sushi(script) do
        capture_stdout { run_task("fsh:verify", @output_dir.to_s) }
      end

      expect(output).to include("SUSHI v0.0.0-stub")
      expect(output).to include("bmi-calculation: 2 Errors, 1 Warnings")
    end

    it "sushi が無ければ中断して理由を出す" do
      expect do
        with_stub_sushi("") do
          ENV["PATH"] = Dir.mktmpdir("empty-bin")
          run_task("fsh:verify", @output_dir.to_s)
        end
      end.to raise_error(SystemExit) { |error| expect(error.message).to include("sushi") }
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
end
