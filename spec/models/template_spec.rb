require "rails_helper"

RSpec.describe Template, type: :model do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }

  describe ".build_from_opt_xml" do
    it "parses template_id, checksum and a web_template with entries/fields from the OPT" do
      template = Template.build_from_opt_xml(opt_xml)

      expect(template.template_id).to be_present
      expect(template.version).to eq("1.0.0")
      expect(template.status).to eq("active")
      expect(template.checksum).to eq(Digest::SHA256.hexdigest(opt_xml))
      expect(template.web_template["entries"]).not_to be_empty
      expect(template.fields).not_to be_empty
      expect(template.fields.first).to include("name", "label", "path", "rm_type", "column_type")
    end

    it "is not yet persisted" do
      template = Template.build_from_opt_xml(opt_xml)
      expect(template).not_to be_persisted
    end

    it "raises InvalidTemplate for XML that isn't an operational template" do
      expect { Template.build_from_opt_xml("<not-an-opt/>") }
        .to raise_error(Template::InvalidTemplate)
    end
  end

  describe "checksum uniqueness" do
    it "rejects a second record with the same source_xml checksum" do
      Template.build_from_opt_xml(opt_xml).save!
      duplicate = Template.build_from_opt_xml(opt_xml)
      duplicate.version = "2.0.0" # different version, same content -> still same checksum

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:checksum]).to be_present
    end
  end

  describe ".find_by_checksum" do
    it "finds an already-registered template by the checksum of its source_xml" do
      saved = Template.build_from_opt_xml(opt_xml).tap(&:save!)
      expect(Template.find_by_checksum(opt_xml)).to eq(saved)
    end

    it "returns nil for content that has not been registered" do
      expect(Template.find_by_checksum("<unregistered/>")).to be_nil
    end
  end

  describe "[template_id, version] uniqueness" do
    it "allows a new version of an already-registered template_id" do
      first = Template.build_from_opt_xml(opt_xml).tap(&:save!)
      second = first.dup
      second.version = "1.1.0"
      second.checksum = "different-checksum-for-spec"

      expect(second).to be_valid
    end
  end
end
