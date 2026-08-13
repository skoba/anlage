require "rails_helper"

RSpec.describe "URL-driven OPT import", type: :system, js: true do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  it "fetches an allowlisted URL server-side and previews it, without a real network call" do
    allow(OpenehrRails::Opt::RemoteFetcher).to receive(:fetch)
      .with("https://ckm.openehr.org/templates/patient_blood_pressure.opt")
      .and_return(opt_path.read)

    visit templates_path
    fill_in placeholder: "https://ckm.openehr.org/...", with: "https://ckm.openehr.org/templates/patient_blood_pressure.opt"
    click_button "URLから取り込む"

    expect(page).to have_content("試着室")
    click_button "登録"

    expect(page).to have_css("#catalog .template-card")
  end
end
