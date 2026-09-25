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

# skoba/anlage#31: 様式11 の欄名（AD がルートに与えた名前）で jp_referral のカードに
# 着地する。container_labels（スキーマ v1.2）を索引対象に含めること。
RSpec.describe Opt::PathcardSearch, "祖先ルート名での着地（#31）" do
  before do
    source_xml = Rails.root.join("spec/fixtures/opt/jp_referral.opt").read
    template = Template.build_from_opt_xml(source_xml)
    template.pathcards = Opt::PathcardExtractor.call(template).cards
    template.save!
  end

  def jp_referral_hits(query)
    described_class.call(query).select { |card| card.dig("identity", "template_id") == "jp_referral" }
                   .map { |card| card.dig("identity").values_at("archetype_id", "at_code") }
  end

  it "既往歴 → story の病歴の記述" do
    expect(jp_referral_hits("既往歴")).to include([ "openEHR-EHR-OBSERVATION.story.v1", "at0004" ])
  end

  it "傷病名 → problem_diagnosis のプロブレム・診断の名称" do
    expect(jp_referral_hits("傷病名")).to include([ "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0002" ])
  end

  it "治療経過 → clinical_synopsis の要約" do
    expect(jp_referral_hits("治療経過")).to include([ "openEHR-EHR-EVALUATION.clinical_synopsis.v1", "at0002" ])
  end

  it "紹介先 → 紹介先医療機関の名称" do
    expect(jp_referral_hits("紹介先")).to include([ "openEHR-EHR-CLUSTER.organisation.v1", "at0001" ])
  end
end
