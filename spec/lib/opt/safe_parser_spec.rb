require "rails_helper"

RSpec.describe Opt::SafeParser do
  let(:source_xml) { Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read }
  let(:doctype_xml) { "<!DOCTYPE template><template/>" }

  describe ".safe_document" do
    it "rejects a DOCTYPE declaration" do
      expect { described_class.safe_document(doctype_xml) }.to raise_error(Opt::UnsafeTemplate)
    end

    it "returns a Nokogiri XML document for a real OPT" do
      expect(described_class.safe_document(source_xml)).to be_a(Nokogiri::XML::Document)
    end
  end

  describe ".parse" do
    it "continues to reject a DOCTYPE declaration" do
      expect { described_class.parse(doctype_xml) }.to raise_error(Opt::UnsafeTemplate)
    end

    it "continues to parse a real OPT" do
      expect(described_class.parse(source_xml)).to be_a(OpenEHR::AM::Template::OperationalTemplate)
    end
  end
end
