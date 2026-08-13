require "rails_helper"

# Plain HTML form submit (no JS needed for this part of the flow), so
# this runs under Capybara's default rack_test driver even in a sandbox
# without a browser installed.
RSpec.describe "OPT-driven forms", type: :system do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }
  let!(:template) { Template.build_from_opt_xml(opt_xml).tap(&:save!) }

  it "rejects an out-of-range value, then accepts a valid submission" do
    visit form_path(template.template_id)

    fill_in "field_blood_pressure_systolic", with: "9999"
    fill_in "field_blood_pressure_diastolic", with: "80"
    fill_in "field_heart_rate_pulse", with: "70"
    click_button "送信"

    expect(page).to have_content("以下である必要があります")
    expect(Composition.count).to eq(0)

    fill_in "field_blood_pressure_systolic", with: "120"
    click_button "送信"

    expect(Composition.count).to eq(1)
    expect(page).to have_content("COMPOSITION")
  end
end
