require "rails_helper"

RSpec.describe Opt::PathcardSearch do
  before do
    %w[CardiologyEncounter LabResultReport ProblemList].each do |name|
      source_xml = Rails.root.join("spec/fixtures/opt/#{name}.opt").read
      template = Template.build_from_opt_xml(source_xml)
      golden = JSON.parse(Rails.root.join("spec/fixtures/pathcards/#{name}.golden.json").read)
      template.pathcards = golden.fetch("cards")
      template.save!
    end
  end

  it "finds the CardiologyEncounter systolic card for 収縮期" do
    expect(identities_for(described_class.call("収縮期"))).to include(
      [ "CardiologyEncounter", "at0004" ]
    )
  end

  it "finds the shorter systolic label by bigram OR matching for 収縮期血圧" do
    expect(identities_for(described_class.call("収縮期血圧"))).to include(
      [ "CardiologyEncounter", "at0004" ]
    )
  end

  it "finds diagnostic certainty through a code-list label" do
    expect(identities_for(described_class.call("疑い"))).to include(
      [ "ProblemList", "at0073" ]
    )
  end

  it "does not bridge the BMI synonym gap" do
    # Phase 2 (embedding) の対象。docs/design/wp3-plan.md参照。
    expect(described_class.call("BMI")).to be_empty
  end

  def identities_for(results)
    results.map do |result|
      identity = result.fetch("identity")
      [ identity.fetch("template_id"), identity.fetch("at_code") ]
    end
  end
end
