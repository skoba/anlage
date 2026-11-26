require "rails_helper"
require "rake"

Rails.application.load_tasks

# rake query_builder:version_candidates（docs/design/s2-cross-version-plan.md 3.1）。候補を Markdown で標準出力に出すだけで、
# 対応の表（config/version_mappings.yml）は書き換えない。
RSpec.describe "query_builder:version_candidates" do
  before do
    %w[CardiologyEncounter patient_blood_pressure ProblemList].each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  subject(:run_task) do
    Rake::Task["query_builder:version_candidates"].reenable
    Rake::Task["query_builder:version_candidates"].invoke
  end

  it "候補の表（アーキタイプ、項目、版、ラベル、型、違い、いまの表での状態）を出す。表のファイルは変えない" do
    table_before = Rails.root.join("config/version_mappings.yml").read

    expect { run_task }.to output(
      a_string_including(
        "# アーキタイプの版の対応の候補（2 件）",
        "| openEHR-EHR-OBSERVATION.blood_pressure | at0004 | v1、v2 | v1: Systolic／v2: 収縮期 | DV_QUANTITY | なし | active |",
        "| openEHR-EHR-OBSERVATION.blood_pressure | at0005 | v1、v2 | v1: Diastolic／v2: 拡張期 | DV_QUANTITY | なし | active |"
      )
    ).to_stdout
    expect(Rails.root.join("config/version_mappings.yml").read).to eq(table_before)
  end
end
