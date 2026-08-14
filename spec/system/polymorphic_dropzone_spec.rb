require "rails_helper"

RSpec.describe "Polymorphic dropzone (composition/ADL)", type: :system, js: true do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }
  let(:adl_path) { Rails.root.join("spec/fixtures/adl/openEHR-EHR-CLUSTER.exam-uterine_cervix.v1.adl") }

  it "shows a dropped composition JSON as a filled-in, read-only form" do
    template = Template.build_from_opt_xml(opt_path.read).tap(&:save!)
    values = template.fields.index_with { "42" }.transform_keys { |f| f["name"] }
    rm_composition = Opt::CompositionBuilder.new(template, values).build
    json = OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize

    composition_file = Tempfile.new([ "composition", ".json" ])
    composition_file.write(json)
    composition_file.flush

    visit templates_path
    attach_file("opt_file_input", composition_file.path, visible: false)

    expect(page).to have_content("記入済みフォーム")
    expect(page).to have_button("閉じる")
    expect(page).not_to have_button("登録")
  end

  it "shows template-ize guidance for a dropped bare ADL archetype" do
    visit templates_path
    attach_file("opt_file_input", adl_path.to_s, visible: false)

    expect(page).to have_content("テンプレート化しますか")
    expect(page).not_to have_button("登録")
  end
end
