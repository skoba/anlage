require "rails_helper"
require "rake"

Rails.application.load_tasks

RSpec.describe "pathcards:backfill" do
  subject(:run_task) do
    Rake::Task["pathcards:backfill"].reenable
    Rake::Task["pathcards:backfill"].invoke
  end

  it "extracts and saves cards for templates whose pathcards are nil" do
    source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
    template = Template.build_from_opt_xml(source_xml).tap(&:save!)

    expect { run_task }
      .to change { template.reload.pathcards }
      .from(nil).to(be_an(Array).and(be_present))
  end

  it "does not update a template whose pathcards are already set" do
    source_xml = Rails.root.join("spec/fixtures/opt/ProblemList.opt").read
    template = Template.build_from_opt_xml(source_xml)
    template.pathcards = []
    template.save!
    original_updated_at = template.updated_at

    run_task

    expect(template.reload.pathcards).to eq([])
    expect(template.updated_at).to eq(original_updated_at)
  end
end
