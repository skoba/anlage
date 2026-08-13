require "rails_helper"

RSpec.describe "Templates", type: :request do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  def upload(path, filename: File.basename(path), type: "text/xml")
    Rack::Test::UploadedFile.new(path.to_s, type, false, original_filename: filename)
  end

  describe "GET /templates" do
    it "renders the (empty) catalog" do
      get templates_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No templates registered yet")
    end
  end

  describe "POST /templates/preview" do
    it "parses a valid OPT and returns a summary without persisting it" do
      post templates_preview_path(format: :json), params: { file: upload(opt_path) }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["template_id"]).to be_present
      expect(body["field_count"]).to be > 0
      expect(body["already_registered"]).to eq(false)
      expect(Template.count).to eq(0)
    end

    it "flags an already-registered template by checksum" do
      Template.build_from_opt_xml(opt_path.read).save!

      post templates_preview_path(format: :json), params: { file: upload(opt_path) }

      expect(response.parsed_body["already_registered"]).to eq(true)
    end

    it "rejects files without .opt/.xml extension" do
      post templates_preview_path(format: :json), params: { file: upload(opt_path, filename: "template.txt") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/\.opt or \.xml/)
    end

    it "rejects files larger than 5MB" do
      Tempfile.create([ "big", ".opt" ]) do |f|
        f.write("a" * (6 * 1024 * 1024))
        f.flush

        post templates_preview_path(format: :json), params: { file: upload(f.path, filename: "big.opt") }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to match(/5MB/)
      end
    end

    it "rejects non-OPT XML with a clear error" do
      Tempfile.create([ "bad", ".xml" ]) do |f|
        f.write("<not-a-template/>")
        f.flush

        post templates_preview_path(format: :json), params: { file: upload(f.path, filename: "bad.xml") }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to be_present
      end
    end

    it "rejects OPT uploads containing a DOCTYPE (XXE defense)" do
      xxe_payload = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE template [
          <!ENTITY xxe SYSTEM "file:///etc/passwd">
        ]>
        <template>
          <concept>&xxe;</concept>
        </template>
      XML

      Tempfile.create([ "xxe", ".opt" ]) do |f|
        f.write(xxe_payload)
        f.flush

        post templates_preview_path(format: :json), params: { file: upload(f.path, filename: "xxe.opt") }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to match(/DOCTYPE/)
        expect(Template.count).to eq(0)
      end
    end
  end
end
