require "rails_helper"

RSpec.describe Opt::PathcardExtractor, "golden regression from CKM fixture OPTs" do
  GOLDEN_CASES = {
    "CardiologyEncounter.opt" => { golden: "CardiologyEncounter.golden.json", count: 2 },
    "LabResultReport.opt" => { golden: "LabResultReport.golden.json", count: 3 },
    "ProblemList.opt" => { golden: "ProblemList.golden.json", count: 6 }
  }.freeze

  GOLDEN_CASES.each do |fixture_name, golden_case|
    describe "#{fixture_name} as the extraction source" do
      it "matches every extracted identity, semantic, constraint, and C2-safe binding" do
        source_path = Rails.root.join("spec/fixtures/opt", fixture_name)
        golden_path = Rails.root.join("spec/fixtures/pathcards", golden_case.fetch(:golden))
        golden = JSON.parse(golden_path.read)
        source_xml = source_path.read
        actual_cards = described_class.call(Template.build_from_opt_xml(source_xml)).cards

        expect(Digest::SHA256.hexdigest(source_xml)).to eq(golden.dig("_provenance", "source_sha256"))
        expect(golden.dig("_provenance", "source_fixture")).to eq(fixture_name)
        expect(golden.dig("_provenance", "binding_origin")).to eq("CKM公開束縛由来")
        expect(actual_cards.size).to eq(golden_case.fetch(:count))
        expect(normalize_for_golden(actual_cards)).to eq(golden.fetch("cards"))
      end
    end
  end

  # C2 (wp2-plan.md 3): the only code_binding literal allowed in any
  # golden file is CardiologyEncounter's at0004 (SNOMED-CT
  # [SNOMED-CT(2003)::271649006]). Every other code_binding's code gets
  # redacted before comparison. Match on (archetype_id, at_code) together,
  # not at_code alone -- at0004 recurs across unrelated archetypes (it's
  # just a local ordinal), so an at_code-only check would fail to mask a
  # different archetype's at0004 code_binding if one existed.
  ALLOWED_LITERAL_CODE_BINDING = {
    "archetype_id" => "openEHR-EHR-OBSERVATION.blood_pressure.v2",
    "at_code" => "at0004"
  }.freeze

  def normalize_for_golden(cards)
    cards.deep_dup.each do |card|
      card.delete("provenance")
      identity = card.fetch("identity")
      next if identity.values_at("archetype_id", "at_code") ==
              ALLOWED_LITERAL_CODE_BINDING.values_at("archetype_id", "at_code")

      card.fetch("bindings").each do |binding|
        binding["code"] = "<REDACTED_SNOMED_CODE>" if binding["kind"] == "code_binding"
      end
    end
  end
end
