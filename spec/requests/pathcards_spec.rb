require "rails_helper"

RSpec.describe "Pathcard search", type: :request do
  it "renders the matching card for a Japanese query" do
    source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
    template = Template.build_from_opt_xml(source_xml)
    golden = JSON.parse(
      Rails.root.join("spec/fixtures/pathcards/CardiologyEncounter.golden.json").read
    )
    template.pathcards = golden.fetch("cards")
    template.save!

    get "/pathcards/search", params: { q: "収縮期" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("収縮期")
    expect(response.body).to include("CardiologyEncounter")
    expect(response.body).to include("at0004")
  end

  it "warns when matching card semantics contain suspected untranslated text" do
    source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
    template = Template.build_from_opt_xml(source_xml)
    golden = JSON.parse(
      Rails.root.join("spec/fixtures/pathcards/LabResultReport.golden.json").read
    )
    template.pathcards = golden.fetch("cards")
    template.save!

    get "/pathcards/search", params: { q: "analyte" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Untranslated text suspected")
  end
end
