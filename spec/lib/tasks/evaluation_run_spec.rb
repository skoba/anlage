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
                         # v1 の q21 ＋ v2 の案の card 4 問（aql の 5 問は RESET 無しでは読まない）。案の確定で変わる（ゴールドに追随する spec 側の数字）
                         "## draft（5 問、母数外）", "## 保留問（2 問、母数外）", "- c019: 検体")
    ).to_stdout

    expect(Rails.root.join("docs/reports").children.map { |path| [ path.basename.to_s, path.mtime ] }.sort).to eq(reports_before)
  end

  it "RESET が無ければ aql の問いは採点せず、その旨を出す" do
    expect { run_task }.to output(a_string_including("aql の問いは RESET=1 のときだけ採点する")).to_stdout
  end

  it "同じ 17 問を match: card（at_code まで見る）でも集計し、情報として並べる（pin ではない）" do
    expect { run_task }.to output(a_string_including("# 評価 v2（phase1-bigram、match: card）", "## card（17 問）")).to_stdout
  end
end
