require "rails_helper"

RSpec.describe "Templates", type: :request do
  let(:opt_path) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt") }

  def upload(path, filename: File.basename(path), type: "text/xml")
    Rack::Test::UploadedFile.new(path.to_s, type, false, original_filename: filename)
  end

  # Derives a "changed content, same template_id" fixture from the real
  # OPT (a targeted label substitution), rather than fabricating one.
  def upload_mutated(original_path, filename: "mutated.opt")
    mutated_xml = original_path.read.sub("Systolic", "Systolic Pressure")
    file = Tempfile.new([ "mutated", ".opt" ])
    file.write(mutated_xml)
    file.flush
    upload(file.path, filename: filename)
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
      expect(Opt::PathcardExtractor).not_to receive(:call)

      post templates_preview_path(format: :json), params: { file: upload(opt_path) }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["template_id"]).to be_present
      expect(body["field_count"]).to be > 0
      expect(body["already_registered"]).to eq(false)
      expect(Template.count).to eq(0)
    end

    it "renders the fitting-room HTML with a live form preview and register/discard buttons" do
      post templates_preview_path, params: { file: upload(opt_path) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("試着室")
      expect(response.body).to include('data-action="click->dropzone#register"')
      expect(response.body).to include('data-action="click->dropzone#discard"')
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

    it "shows a semantic diff when the template_id matches an active template but the content differs" do
      Template.build_from_opt_xml(opt_path.read).save!

      post templates_preview_path, params: { file: upload_mutated(opt_path) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v1.0.1")
      expect(response.body).to include("Systolic Pressure")
    end

    it "fetches from an allowlisted URL server-side and previews it" do
      allow(OpenehrRails::Opt::RemoteFetcher).to receive(:fetch)
        .with("https://ckm.openehr.org/templates/patient_blood_pressure.opt")
        .and_return(opt_path.read)

      post templates_preview_path(format: :json),
           params: { url: "https://ckm.openehr.org/templates/patient_blood_pressure.opt" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["template_id"]).to be_present
      expect(Template.count).to eq(0)
    end

    it "rejects a URL on a host outside the allowlist without fetching it" do
      expect(OpenehrRails::Opt::RemoteFetcher).not_to receive(:fetch)

      post templates_preview_path(format: :json), params: { url: "https://evil.example.com/x.opt" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/ckm\.openehr\.org/)
    end

    it "surfaces a RemoteFetcher failure as a validation error" do
      allow(OpenehrRails::Opt::RemoteFetcher).to receive(:fetch)
        .and_raise(OpenehrRails::Opt::RemoteFetcher::FetchError, "failed to fetch: 404 Not Found")

      post templates_preview_path(format: :json), params: { url: "https://ckm.openehr.org/missing.opt" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/404/)
    end
  end

  describe "POST /templates" do
    it "registers a template fetched from an allowlisted URL" do
      allow(OpenehrRails::Opt::RemoteFetcher).to receive(:fetch)
        .with("https://ckm.openehr.org/templates/patient_blood_pressure.opt")
        .and_return(opt_path.read)

      post templates_path(format: :json),
           params: { url: "https://ckm.openehr.org/templates/patient_blood_pressure.opt" }

      expect(response).to have_http_status(:created)
      expect(Template.count).to eq(1)
    end

    it "registers a new template and returns it as created" do
      post templates_path(format: :json), params: { file: upload(opt_path) }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["template_id"]).to be_present
      expect(Template.count).to eq(1)
      expect(Template.last.pathcards).to be_present
    end

    it "renders a turbo-stream that appends a catalog card" do
      post templates_path, params: { file: upload(opt_path) }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('turbo-stream action="append" target="catalog"')
      expect(Template.count).to eq(1)
    end

    it "does not create a duplicate when the same checksum is dropped again" do
      Template.build_from_opt_xml(opt_path.read).save!
      expect(Opt::PathcardExtractor).not_to receive(:call)

      post templates_path(format: :json), params: { file: upload(opt_path) }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["notice"]).to match(/already registered/)
      expect(Template.count).to eq(1)
    end

    it "rejects a DOCTYPE payload the same way preview does" do
      xxe_payload = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE template [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        <template><concept>&xxe;</concept></template>
      XML

      Tempfile.create([ "xxe", ".opt" ]) do |f|
        f.write(xxe_payload)
        f.flush

        post templates_path(format: :json), params: { file: upload(f.path, filename: "xxe.opt") }

        expect(response).to have_http_status(:unprocessable_content)
        expect(Template.count).to eq(0)
      end
    end

    it "registers a new version and supersedes the previous one when content for the same template_id changes" do
      original = Template.build_from_opt_xml(opt_path.read).tap(&:save!)

      post templates_path(format: :json), params: { file: upload_mutated(opt_path) }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["version"]).to eq("1.0.1")
      expect(Template.count).to eq(2)
      expect(original.reload.status).to eq("superseded")
      replacement = Template.active.find_by(template_id: original.template_id)
      expect(replacement.version).to eq("1.0.1")
      expect(replacement.pathcards).to be_present
    end

    it "registers the template without pathcards when extraction fails" do
      allow(Opt::PathcardExtractor).to receive(:call).and_raise(StandardError, "extraction failed")
      allow(Rails.logger).to receive(:warn)

      post templates_path(format: :json), params: { file: upload(opt_path) }

      expect(response).to have_http_status(:created)
      expect(Template.last.pathcards).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/extraction failed/)
    end

    it "removes the superseded template's card and appends the new version's card via turbo-stream" do
      original = Template.build_from_opt_xml(opt_path.read).tap(&:save!)

      post templates_path, params: { file: upload_mutated(opt_path) }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include(%(turbo-stream action="remove" target="template_#{original.id}"))
      expect(response.body).to include('turbo-stream action="append" target="catalog"')
    end
  end
end
