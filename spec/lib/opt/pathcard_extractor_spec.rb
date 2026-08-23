require "rails_helper"

RSpec.describe Opt::PathcardExtractor do
  describe ".call" do
    it "returns schema-v1 shaped pathcards for the CardiologyEncounter OPT" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.cards).to be_an(Array)
      expect(result.cards).not_to be_empty
      expect(result.cards).to all(
        include(
          "schema_version" => "1.0",
          "identity" => be_a(Hash),
          "semantics" => be_a(Hash),
          "constraints" => be_a(Hash),
          "bindings" => be_an(Array),
          "capture" => be_a(Hash),
          "reserved" => be_a(Hash),
          "provenance" => be_a(Hash)
        )
      )
    end
  end
end
