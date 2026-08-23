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

    it "extracts the blood pressure systolic identity from CardiologyEncounter" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.cards).to include(
        include(
          "identity" => {
            "template_id" => "CardiologyEncounter",
            "archetype_id" => "openEHR-EHR-OBSERVATION.blood_pressure.v2",
            "path" => "/content[openEHR-EHR-OBSERVATION.blood_pressure.v2]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value",
            "at_code" => "at0004"
          }
        )
      )
    end

    it "tracks the embedded laboratory analyte archetype identity in LabResultReport" do
      source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.cards).to include(
        include(
          "identity" => {
            "template_id" => "LabResultReport",
            "archetype_id" => "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1",
            "path" => "/content[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]/data[at0001]/events[at0002]/data[at0003]/items[at0000]/items[at0001]/value",
            "at_code" => "at0001"
          }
        )
      )
    end
  end
end
