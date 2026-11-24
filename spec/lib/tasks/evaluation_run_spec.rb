require "rails_helper"
require "rake"

Rails.application.load_tasks

# rake evaluation:run（docs/design/s1-eval-v2-plan.md 2.5）。報告は標準出力だけで、docs/reports/ には書かない。
# aql の問いは dataset を作り直す（dev DB を壊す）ので、RESET=1 のときだけ採点する。
RSpec.describe "evaluation:run" do
  before do
    %w[bmi_calculation ProblemList CardiologyEncounter LabResultReport].each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  subject(:run_task) do
    Rake::Task["evaluation:run"].reenable
    Rake::Task["evaluation:run"].invoke
  end

  it "v1 の 17 問の集計を Markdown で標準出力に出し、docs/reports/ のファイルは変えない" do
    reports_before = Rails.root.join("docs/reports").children.map { |path| [ path.basename.to_s, path.mtime ] }.sort

    expect { run_task }.to output(
      a_string_including("# 評価 v2（phase1-bigram）", "## card（17 問）", "| Top-1 | 14/17 (82.35%) |", "| Top-3 | 15/17 (88.24%) |",
                         "| 完全失敗 | 2/17 (11.76%) |", "| MRR | 0.8529 |", "- q16: BMI", "- q18: 既往",
                         "## draft（0 問、母数外）")
    ).to_stdout

    expect(Rails.root.join("docs/reports").children.map { |path| [ path.basename.to_s, path.mtime ] }.sort).to eq(reports_before)
  end

  # v1 の 17 問の表を保つため、ゴールド v2 は別の報告にする（R-20261124-15。v1 の採点結果が変わらないことの pin は上の例）。
  # この spec の索引は 4 テンプレートで、c015「臨床検査」は負例（ProblemList at0003）が 1 位に出る（bigram「臨床」の偽陽性の実物）。
  # demo_initial の 5 テンプレートでは 1 位が laboratory_test_result で負例違反は無い（spec/lib/evaluation/runner_spec.rb）
  it "ゴールド v2 の card 4 問は別の報告に出し、保留問 2 問を並べる（aql は RESET 無しでは読まない）" do
    expect { run_task }.to output(
      a_string_including("# 評価 v2（phase1-bigram、ゴールド v2）", "## card（4 問）", "| Top-1 | 3/4 (75.00%) |", "| Top-3 | 4/4 (100.00%) |",
                         "| 負例違反 | 1/4 |", "- c015: 臨床検査 → openEHR-EHR-EVALUATION.problem_diagnosis.v1 at0003",
                         "| 順位遵守 | 1/1 (100.00%)（組 1/1） |", "## 保留問（2 問、母数外）", "- c019: 検体", "- c021: 既往歴")
    ).to_stdout
  end

  it "RESET が無ければ aql の問いは採点せず、その旨を出す" do
    expect { run_task }.to output(a_string_including("aql の問いは RESET=1 のときだけ採点する")).to_stdout
  end

  it "同じ 17 問を match: card（at_code まで見る）でも集計し、情報として並べる（pin ではない）" do
    expect { run_task }.to output(a_string_including("# 評価 v2（phase1-bigram、match: card）", "## card（17 問）")).to_stdout
  end
end
