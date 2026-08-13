require "rails_helper"

RSpec.describe "FHIR StructureDefinition", type: :request do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }
  let!(:template) { Template.build_from_opt_xml(opt_xml).tap(&:save!) }

  it "generates a StructureDefinition for a registered template's archetype, derived from its OPT" do
    opt = OpenehrRails::Opt.parse(opt_xml)
    profile_id = OpenehrRails::Fhir::ProfileGenerator.new(opt).profiles.first[:id]

    get "/fhir/r5/StructureDefinition/#{profile_id}"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/fhir+json")
    body = JSON.parse(response.body)
    expect(body["resourceType"]).to eq("StructureDefinition")
    expect(body["id"]).to eq(profile_id)
  end

  it "returns a FHIR OperationOutcome 404 for an unknown id" do
    get "/fhir/r5/StructureDefinition/does-not-exist"

    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)["resourceType"]).to eq("OperationOutcome")
  end
end
