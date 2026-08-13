require "rails_helper"

# Multiple files chosen/dropped at once are queued and previewed one at
# a time, so the visitor isn't shown N fitting rooms simultaneously.
# Only one local fixture is available, so this drops it twice -- still
# exercises the real queueing mechanism (advance-on-register /
# advance-on-discard) even though the second entry ends up a checksum
# duplicate of the first.
RSpec.describe "Multi-file OPT dropzone", type: :system, js: true do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  it "previews each queued file in turn after the current one is registered" do
    visit templates_path

    attach_file("opt_file_input", [ opt_path.to_s, opt_path.to_s ], visible: false)

    expect(page).to have_content("試着室")
    expect(page).to have_content("残り1件")

    click_button "登録"

    expect(page).to have_css("#catalog .template-card")
    expect(page).to have_content("登録済み")
    expect(page).not_to have_content("残り")
  end
end
