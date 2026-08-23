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
          },
          "constraints" => {
            "occurrences" => { "lower" => 0, "upper" => 1 },
            "value" => {
              "property" => { "terminology" => "openehr", "code" => "125" },
              "units" => "mm[Hg]",
              "magnitude_range" => {
                "lower" => 0.0,
                "upper" => 1000.0,
                "lower_included" => true,
                "upper_included" => false
              },
              "precision_range" => { "lower" => 0, "upper" => 0 }
            }
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

    it "extracts the Japanese systolic label from CardiologyEncounter" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-OBSERVATION.blood_pressure.v2" &&
          candidate.dig("identity", "at_code") == "at0004"
      end

      expect(card.dig("semantics", "labels")).to eq([
        {
          "lang" => "ja",
          "text" => "収縮期",
          "untranslated_suspect" => false,
          "untranslated_evidence" => nil,
          "source_lang" => nil
        }
      ])
    end

    it "extracts the fallback-marked analyte description from LabResultReport" do
      source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1" &&
          candidate.dig("identity", "at_code") == "at0001"
      end

      expect(card.dig("semantics", "descriptions")).to eq([
        {
          "lang" => "ja",
          "text" => "*The value of the analyte result. (en)",
          "untranslated_suspect" => true,
          "untranslated_evidence" => "fallback_marker",
          "source_lang" => "en"
        }
      ])
    end

    it "extracts the local code list for diagnostic certainty from ProblemList" do
      source_xml = Rails.root.join("spec/fixtures/opt/ProblemList.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" &&
          candidate.dig("identity", "at_code") == "at0073"
      end

      expect(card.dig("constraints", "value")).to eq(
        "code_list" => [
          { "code" => "at0074", "label" => "疑い" },
          { "code" => "at0075", "label" => "推定" },
          { "code" => "at0076", "label" => "確定" }
        ]
      )
    end
  end

  describe "#classify_translation" do
    subject(:classification) do
      described_class.new(nil).send(:classify_translation, text)
    end

    context "when text has a fallback marker and source language" do
      let(:text) { "*Foo bar (en)" }

      it do
        expect(classification).to eq(
          "untranslated_suspect" => true,
          "untranslated_evidence" => "fallback_marker",
          "source_lang" => "en"
        )
      end
    end

    context "when unmarked text contains no Japanese script" do
      let(:text) { "Foo bar" }

      it do
        expect(classification).to eq(
          "untranslated_suspect" => true,
          "untranslated_evidence" => "no_ja_script",
          "source_lang" => nil
        )
      end
    end

    context "when text contains Japanese script" do
      let(:text) { "収縮期" }

      it do
        expect(classification).to eq(
          "untranslated_suspect" => false,
          "untranslated_evidence" => nil,
          "source_lang" => nil
        )
      end
    end
  end
end
