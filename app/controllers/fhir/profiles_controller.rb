module Fhir
  # HL7 FHIR R5 StructureDefinition generation, derived on the fly from
  # each registered template's own OPT (OpenehrRails::Fhir::ProfileGenerator
  # only needs the parsed OperationalTemplate -- no scaffolded model or
  # FIELD_MAP -- so it's directly reusable from the interpretation path).
  # A full FHIR REST facade (search/create Observations etc.) depends on
  # OpenehrRails::Fhir::ResourceRegistry, which *does* require scaffolded
  # models; that's out of scope here (see docs/plans/opt-dropzone.md).
  class ProfilesController < ApplicationController
    FHIR_CONTENT_TYPE = "application/fhir+json"

    def show
      profile = all_profiles.find { |p| p[:id] == params[:id] }
      unless profile
        return render json: operation_outcome("StructureDefinition/#{params[:id]} not found"),
                       status: :not_found, content_type: FHIR_CONTENT_TYPE
      end

      render json: profile, content_type: FHIR_CONTENT_TYPE
    end

    private

    def all_profiles
      Template.active.flat_map do |template|
        opt = OpenehrRails::Opt.parse(template.source_xml)
        OpenehrRails::Fhir::ProfileGenerator.new(opt).profiles
      end
    end

    def operation_outcome(diagnostics)
      {
        resourceType: "OperationOutcome",
        issue: [ { severity: "error", code: "not-found", diagnostics: diagnostics } ]
      }
    end
  end
end
