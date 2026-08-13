require "rails_helper"

RSpec.describe "Forms and Compositions", type: :request do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }
  let!(:template) { Template.build_from_opt_xml(opt_xml).tap(&:save!) }

  def valid_values
    template.fields.index_with { |field| field["rm_type"] == "DV_QUANTITY" ? "120" : "some text" }
              .transform_keys { |field| field["name"] }
  end

  describe "GET /forms/:template_id" do
    it "renders a working form built from the template's web_template" do
      get form_path(template.template_id)

      expect(response).to have_http_status(:ok)
      template.fields.each do |field|
        expect(response.body).to include(%(name="values[#{field['name']}]"))
      end
    end

    it "404s for an unregistered template_id" do
      get form_path("does-not-exist")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /compositions/:template_id" do
    it "rejects an out-of-range value with a per-field validation message" do
      values = valid_values
      quantity_field = template.fields.find { |f| f["rm_type"] == "DV_QUANTITY" && f["magnitude_range"]&.last }
      values[quantity_field["name"]] = (quantity_field["magnitude_range"][1] + 1000).to_s

      post template_compositions_path(template.template_id), params: { values: values }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("field-error-message")
      expect(Composition.count).to eq(0)
    end

    # Required-field and coded-text validation branches are covered at
    # the unit level (spec/lib/opt/form_validator_spec.rb) since none of
    # the fields in the local blood-pressure fixture are required or
    # coded-text.

    it "builds and persists a canonical RM composition, then shows it" do
      post template_compositions_path(template.template_id), params: { values: valid_values }

      expect(response).to redirect_to(composition_path(Composition.last))
      composition = Composition.last
      expect(composition.template).to eq(template)
      expect(composition.rm_composition["_type"]).to eq("COMPOSITION")

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("COMPOSITION")
    end
  end

  describe "GET /compositions" do
    it "lists registered compositions" do
      post template_compositions_path(template.template_id), params: { values: valid_values }

      get compositions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(template.template_id)
    end
  end
end
