require "rails_helper"

# JS-driven (drag&drop → fitting room → register → Turbo Stream card).
# Drag&drop itself can't be scripted portably across browsers, so this
# exercises the click-to-choose path (same controller actions, same
# server round trips) via the hidden file input.
RSpec.describe "OPT dropzone", type: :system, js: true do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  it "previews a dropped OPT and registers it without a page reload" do
    visit templates_path
    expect(page).to have_content("No templates registered yet")

    attach_file("opt_file_input", opt_path.to_s, visible: false)

    expect(page).to have_content("試着室")
    expect(page).to have_content("archetype検出") # the parse-log reveal, before the form appears
    expect(page).to have_button("登録")

    click_button "登録"

    expect(page).to have_css("#catalog .template-card")
    expect(page).not_to have_content("No templates registered yet")
  end

  it "notifies when the same checksum is dropped again" do
    Template.build_from_opt_xml(opt_path.read).save!
    visit templates_path

    attach_file("opt_file_input", opt_path.to_s, visible: false)

    expect(page).to have_content("登録済み")
  end
end
