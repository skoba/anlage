require "rails_helper"

# JS-driven (drag&drop → fitting room → register → Turbo Stream card).
# Requires a headless Chrome/Chromium; not runnable in this sandbox
# (no browser installed here) -- run in CI or a dev machine with Chrome.
RSpec.describe "OPT dropzone", type: :system, js: true do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  it "previews a dropped OPT and registers it without a page reload" do
    visit templates_path
    expect(page).to have_content("No templates registered yet")

    attach_file(nil, opt_path.to_s) do
      find("#dropzone_hint").click
    end

    expect(page).to have_content("試着室")
    expect(page).to have_button("登録")

    click_button "登録"

    expect(page).to have_css("#catalog .template-card")
    expect(page).not_to have_content("No templates registered yet")
  end

  it "notifies when the same checksum is dropped again" do
    Template.build_from_opt_xml(opt_path.read).save!
    visit templates_path

    attach_file(nil, opt_path.to_s) do
      find("#dropzone_hint").click
    end

    expect(page).to have_content("登録済み")
  end
end
