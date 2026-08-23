require "rails_helper"
require "rake"
require "yaml"

Rails.application.load_tasks

RSpec.describe "pathcards:eval" do
  let(:seed_path) { Rails.root.join("spec/fixtures/pathcards_eval_seed.yml") }
  let(:entries) { YAML.load_file(seed_path) }
  let(:report_path) { Rails.root.join("docs/reports/wp4-eval-log.md") }

  # テストTODO:
  # - 評価シードの必須キーを固定する
  # - 正解archetype_idが現有4テンプレートの実抽出結果に存在することを固定する
  # - 20問の実測集計値と完全失敗一覧を固定する
  # - 評価ログへの追記を固定する

  it "評価シードの全エントリが必須キーを持つ" do
    expect(entries).not_to be_empty
    expect(entries).to all(include("id", "query", "expected_archetype_id"))
    expect(entries).to all(satisfy do |entry|
      entry.values_at("id", "query", "expected_archetype_id").all?(&:present?)
    end)
  end

  it "全ての正解archetype_idが現有4テンプレートの実抽出結果に存在する" do
    fixture_names = %w[CardiologyEncounter LabResultReport ProblemList bmi_calculation]
    actual_archetype_ids = fixture_names.flat_map do |fixture_name|
      source_xml = Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read
      template = Template.build_from_opt_xml(source_xml)
      Opt::PathcardExtractor.call(template).cards.map { |card| card.dig("identity", "archetype_id") }
    end.uniq

    expect(entries.map { |entry| entry.fetch("expected_archetype_id") }.uniq)
      .to be_all { |archetype_id| actual_archetype_ids.include?(archetype_id) }
  end

  context "現有4テンプレートが索引済みの場合" do
    before do
      # q15は同点カードの既存DB順も含む現行Phase 1の実測を固定する。
      %w[bmi_calculation ProblemList CardiologyEncounter LabResultReport].each do |fixture_name|
        source_xml = Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read
        template = Template.build_from_opt_xml(source_xml)
        template.pathcards = Opt::PathcardExtractor.call(template).cards
        template.save!
      end
    end

    around do |example|
      original_report = report_path.binread if report_path.exist?
      report_path.delete if report_path.exist?
      example.run
    ensure
      if original_report
        report_path.binwrite(original_report)
      elsif report_path.exist?
        report_path.delete
      end
    end

    subject(:run_task) do
      Rake::Task["pathcards:eval"].reenable
      Rake::Task["pathcards:eval"].invoke
    end

    it "20問の実測集計値と完全失敗問題を表示する" do
      expect { run_task }.to output(
        a_string_including(
          "Top-1 accuracy: 15/20 (75.00%)",
          "Top-3 accuracy: 16/20 (80.00%)",
          "Complete failure rate: 4/20 (20.00%)",
          "MRR: 0.7750",
          "bigram成立想定: 11/11",
          "複合語: 5/5",
          "同義語ギャップ: 0/4",
          "q16: BMI",
          "q17: 体格指数",
          "q18: 既往",
          "q19: 検体"
        )
      ).to_stdout
    end

    it "比較可能な評価エントリをレポートへ追記する" do
      expect { run_task }.to change { report_path.exist? }.from(false).to(true)

      report = report_path.read
      expect(report).to include(
        "# WP4 パスカード検索評価ログ",
        "検索実装: `phase1-bigram`",
        "Top-1精度: 15/20 (75.00%)",
        "Top-3精度: 16/20 (80.00%)",
        "完全失敗率: 4/20 (20.00%)",
        "MRR: 0.7750",
        "bigram成立想定: 11/11",
        "複合語: 5/5",
        "同義語ギャップ: 0/4"
      )
    end
  end
end
