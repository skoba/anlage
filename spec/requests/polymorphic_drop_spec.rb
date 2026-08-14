require "rails_helper"

RSpec.describe "Polymorphic dropzone", type: :request do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }
  let(:adl_path) { Rails.root.join("spec/fixtures/adl/openEHR-EHR-CLUSTER.exam-uterine_cervix.v1.adl") }

  def upload(path, filename: File.basename(path), type: "text/xml")
    Rack::Test::UploadedFile.new(path.to_s, type, false, original_filename: filename)
  end

  describe "dropping a canonical composition JSON" do
    it "shows it as a filled-in form for the matching registered template" do
      template = Template.build_from_opt_xml(opt_path.read).tap(&:save!)
      values = template.fields.index_with { "42" }.transform_keys { |f| f["name"] }
      rm_composition = Opt::CompositionBuilder.new(template, values).build
      json = OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize

      file = Tempfile.new([ "composition", ".json" ])
      file.write(json)
      file.flush

      post templates_preview_path, params: { file: upload(file.path, filename: "composition.json", type: "application/json") }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("記入済みフォーム")
      expect(response.body).to include('value="42.0"')
      expect(Template.count).to eq(1) # no new template registered
    end

    it "rejects a composition whose template isn't registered" do
      template = Template.build_from_opt_xml(opt_path.read) # not saved
      values = template.fields.index_with { "1" }.transform_keys { |f| f["name"] }
      rm_composition = Opt::CompositionBuilder.new(template, values).build
      json = OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize

      file = Tempfile.new([ "composition", ".json" ])
      file.write(json)
      file.flush

      post templates_preview_path(format: :json),
           params: { file: upload(file.path, filename: "composition.json", type: "application/json") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/no registered template/)
    end
  end

  describe "dropping a bare ADL archetype" do
    it "shows a template-ize guidance message instead of a form" do
      post templates_preview_path, params: { file: upload(adl_path, type: "text/plain") }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("openEHR-EHR-CLUSTER.exam-uterine_cervix.v1")
      expect(response.body).to include("テンプレート化しますか")
      expect(Template.count).to eq(0)
    end
  end
end
